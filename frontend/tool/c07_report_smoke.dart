// Opt-in emulator probe. Build ONLY as a separate temporary QA Android app.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/report_controller.dart';
import 'package:simanja/core/transaction_report.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/profile_repository.dart';
import 'package:simanja/repositories/transaction_repository.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  debugPrint('C07_NATIVE_CHECK $label');
}

Future<void> waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('probe-wait-timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('C07_NATIVE_TEST')) {
    throw StateError('probe-opt-in-required');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('C07 report SDK probe'))),
    ),
  );
  try {
    await probe();
  } catch (error) {
    debugPrint(
      'C07_NATIVE_FAIL ${error is FirebaseException ? error.code : error.runtimeType}',
    );
    if (error is StateError) debugPrint('C07_NATIVE_ASSERT ${error.message}');
  }
}

Future<void> probe() async {
  final app = await Firebase.initializeApp(
    name: defaultFirebaseAppName,
    demoProjectId: 'demo-simanja',
  );
  check(app.options.projectId == 'demo-simanja', 'demo-project');
  const host = String.fromEnvironment(
    'C07_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  check(['10.0.2.2', '127.0.0.1'].contains(host), 'loopback-target');
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.useFirestoreEmulator(host, 8080);
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final user = (await auth.createUserWithEmailAndPassword(
    email: 'c07-$nonce@example.test',
    password: 'C07-Fixture-Password123!',
  )).user!;
  final uid = user.uid;
  final collection = db.collection('users').doc(uid).collection('transactions');
  TransactionModel row(int i) => TransactionModel(
    id: 'qa-${i.toString().padLeft(3, '0')}',
    category: 'Gaji',
    description: (i == 0 || i == 120) ? 'needle' : 'C07 fixture',
    amount: i == 0
        ? 9007199254740991
        : i == 1
        ? 2
        : 1,
    isIncome: true,
    date: DateTime.utc(2026, 11, 27),
  );
  final batch = db.batch();
  for (var i = 0; i < 121; i++) {
    batch.set(collection.doc(row(i).id), {
      ...TransactionMapper.toMap(row(i)),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'revision': 1,
    });
  }
  await batch.commit();
  final repository = FirestoreTransactionRepository(db);
  final state = AppState.instance;
  state.useProfileRepository(FirestoreProfileRepository(db));
  state.useTransactionRepository(repository);
  await state.beginSession(uid, user.email!);
  await waitFor(
    () => state.transactionsServerConfirmed && state.transactions.length == 121,
  );
  final controller = ReportController(state);
  try {
    await waitFor(() => !controller.loadingPage);
    check(
      controller.usesServerPaging && controller.pageNotice == null,
      'canonical-paging-enabled',
    );
    check(
      controller.visibleRows.length == 50 &&
          controller.report.rows.length == 121,
      'page-not-report',
    );
    final total = BigInt.from(9007199254740991) + BigInt.from(121);
    check(
      controller.report.income == total && state.totalIncome == total,
      'exact-full-total',
    );
    final seen = <String>{...controller.visibleRows.map((row) => row.id)};
    await controller.nextPage();
    check(
      controller.usesServerPaging && controller.pageNotice == null,
      'real-query-integrated',
    );
    seen.addAll(controller.visibleRows.map((row) => row.id));
    check(
      controller.firstRow == 51 && controller.report.income == total,
      'second-page-full-total',
    );
    await controller.nextPage();
    seen.addAll(controller.visibleRows.map((row) => row.id));
    check(
      seen.length == 121 && controller.visibleRows.length == 21,
      'all-pages-exactly-once',
    );
    final frozen = controller.captureExport();
    final csv = utf8.decode(CsvExporter.encode(frozen.rows, 'November 2026'));
    check(
      csv.contains('# Jumlah baris: 121') && csv.contains('9007199254740991'),
      'csv-all-rows-exact-money',
    );
    controller.configure(ReportCriteria(search: 'needle'));
    check(
      controller.report.rows.length == 2 &&
          controller.report.income ==
              BigInt.from(9007199254740991) + BigInt.one,
      'search-entire-scope',
    );
    controller.configure(ReportCriteria());
    await waitFor(() => !controller.loadingPage);
    await db.disableNetwork();
    await waitFor(() => controller.report.source.fromCache);
    check(
      !controller.report.source.canExport && !controller.usesServerPaging,
      'cache-not-complete-export-disabled',
    );
    var blocked = false;
    try {
      controller.captureExport();
    } on StateError {
      blocked = true;
    }
    check(blocked, 'cache-export-rejected');
    await db.enableNetwork();
    await waitFor(
      () => controller.report.source.canExport && !controller.loadingPage,
    );
    check(
      controller.captureExport().rows.length == 121,
      'reconnect-complete-report',
    );
    await controller.nextPage();
    final legacy = {
      ...TransactionMapper.toMap(row(122)),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'revision': 1,
    };
    legacy.remove('dateVersion');
    await collection.doc('legacy').set(legacy);
    await waitFor(
      () =>
          controller.report.rows.length == 122 &&
          controller.report.source.canExport,
    );
    check(
      controller.firstRow == 1 && !controller.usesServerPaging,
      'realtime-legacy-resets-page',
    );
    check(
      controller.report.income == total + BigInt.one &&
          controller.captureExport().rows.length == 122,
      'legacy-included-in-total-and-export',
    );
    check(
      frozen.rows.length == 121 && frozen.income == total,
      'frozen-export-survives-realtime',
    );
    final oldRevision = frozen.source.sessionRevision;
    state.clearSession();
    await state.beginSession(uid, user.email!);
    await waitFor(
      () =>
          controller.report.source.canExport &&
          controller.report.rows.length == 122,
    );
    check(
      oldRevision != state.sessionRevision &&
          frozen.source.uid == state.sessionUid,
      'same-uid-new-session-distinguished',
    );
    await state.retryTransactions();
    await waitFor(() => controller.report.source.canExport);
    check(controller.report.rows.length == 122, 'reload-remains-complete');
  } finally {
    controller.dispose();
    state.clearSession();
    await auth.signOut();
  }
  debugPrint('C07_NATIVE_PASS');
}
