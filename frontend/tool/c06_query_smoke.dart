// Emulator-only entry point for a separate temporary QA application.
// Never install this using the SIMANJA application ID or a cloud project.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:simanja/models/transaction_history.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  debugPrint('C06_NATIVE_CHECK $label');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('C06_NATIVE_TEST')) {
    throw StateError('emulator-probe-opt-in-required');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('C06 query SDK probe'))),
    ),
  );
  try {
    await probe();
  } catch (error) {
    debugPrint(
      'C06_NATIVE_FAIL ${error is FirebaseException ? error.code : error.runtimeType}',
    );
    if (error is StateError) debugPrint('C06_NATIVE_ASSERT ${error.message}');
  }
}

Future<void> probe() async {
  final app = await Firebase.initializeApp(
    name: defaultFirebaseAppName,
    demoProjectId: 'demo-simanja',
  );
  check(app.options.projectId == 'demo-simanja', 'demo-project');
  const host = String.fromEnvironment(
    'C06_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  check(['10.0.2.2', '127.0.0.1'].contains(host), 'loopback-target');
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.useFirestoreEmulator(host, 8080);
  db.settings = const Settings(persistenceEnabled: false);
  final user = (await auth.signInAnonymously()).user!;
  final uid = user.uid;
  final repository = FirestoreTransactionRepository(db);
  TransactionModel row(String id, {DateTime? date}) => TransactionModel(
    id: id,
    category: 'Gaji',
    description: 'C06 synthetic fixture',
    amount: 100,
    isIncome: true,
    date: date ?? DateTime.utc(2026, 11, 27),
  );
  for (final id in ['a', 'b', 'c', 'd', 'e']) {
    await repository.add(uid, row(id));
  }
  await repository.add(uid, row('start', date: DateTime.utc(2026, 11)));
  await repository.add(uid, row('end', date: DateTime.utc(2026, 12)));
  final collection = db.collection('users').doc(uid).collection('transactions');
  final legacy = {
    ...TransactionMapper.toMap(row('legacy')),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'revision': 1,
  };
  legacy.remove('dateVersion');
  await collection.doc('legacy').set(legacy);
  final query = TransactionHistoryQuery(
    from: DateTime(2026, 11),
    until: DateTime(2026, 12),
    pageSize: 2,
  );
  final first = await repository.loadHistory(uid, query);
  check(
    first.transactions.map((row) => row.id).join(',') == 'e,d',
    'tie-id-sort',
  );
  check(first.fetchedDocuments == 3 && first.hasMore, 'bounded-lookahead');
  check(
    first.serverConfirmed && !first.isCompleteForCanonicalRange,
    'partial-not-total',
  );
  check(!first.includesLegacyDates, 'legacy-coverage-explicit');
  final collected = [...first.transactions.map((row) => row.id)];
  var cursor = first.nextCursor;
  while (cursor != null) {
    final next = await repository.loadHistory(uid, query, after: cursor);
    collected.addAll(next.transactions.map((row) => row.id));
    check(!next.isCompleteForCanonicalRange, 'following-page-not-total');
    cursor = next.nextCursor;
  }
  check(collected.join(',') == 'e,d,c,b,a,start', 'all-static-ids-once');
  check(!collected.contains('end'), 'range-end-exclusive');
  check(!collected.contains('legacy'), 'legacy-not-silently-mixed');
  final all = await repository
      .watch(uid)
      .firstWhere((value) => !value.fromCache);
  check(
    all.transactions.length == 8 &&
        all.transactions.any((row) => row.needsDateReview),
    'facade-still-complete-mixed-schema',
  );
  final boundary = first.transactions.last;
  await repository.delete(uid, boundary.id, expectedVersion: boundary.version);
  final next = await repository.loadHistory(
    uid,
    query,
    after: first.nextCursor,
  );
  check(
    next.transactions.map((row) => row.id).join(',') == 'c,b',
    'deleted-boundary-cursor',
  );
  await repository.add(uid, row('z'));
  final afterInsert = await repository.loadHistory(
    uid,
    query,
    after: first.nextCursor,
  );
  check(
    afterInsert.transactions.map((row) => row.id).join(',') == 'c,b',
    'insert-before-needs-refresh',
  );
  final refreshed = await repository.loadHistory(uid, query);
  check(refreshed.transactions.first.id == 'z', 'refresh-sees-new-leading-row');
  final empty = await repository.loadHistory(
    uid,
    TransactionHistoryQuery(
      from: DateTime.utc(2030),
      until: DateTime.utc(2031),
    ),
  );
  check(
    empty.transactions.isEmpty &&
        empty.isCompleteForCanonicalRange &&
        empty.nextCursor == null,
    'empty-server-range',
  );
  var scopeRejected = false;
  try {
    await repository.loadHistory(
      uid,
      TransactionHistoryQuery(),
      after: first.nextCursor,
    );
  } on ArgumentError {
    scopeRejected = true;
  }
  check(scopeRejected, 'changed-range-cursor-rejected');
  await auth.signOut();
  final other = (await auth.signInAnonymously()).user!;
  check(other.uid != uid, 'two-distinct-owners');
  var denied = false;
  try {
    await repository.loadHistory(uid, query);
  } on FirebaseException catch (error) {
    denied = error.code == 'permission-denied';
  }
  check(denied, 'foreign-owner-denied');
  final own = await repository.loadHistory(other.uid, query);
  check(own.transactions.isEmpty && own.serverConfirmed, 'other-owner-no-leak');
  await auth.signOut();
  debugPrint('C06_NATIVE_PASS');
}
