// Opt-in QA package only. Three REAL process runs, no clearing QA app data.
// First run seeds a legacy disk cache; next runs use the production policy.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/firestore_cache_policy.dart';
import 'package:simanja/core/session_artifacts.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/profile_repository.dart';
import 'package:simanja/repositories/transaction_repository.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  debugPrint('C08_NATIVE_CHECK $label');
}

Future<void> waitFor(bool Function() predicate) async {
  final until = DateTime.now().add(const Duration(seconds: 40));
  while (!predicate()) {
    if (DateTime.now().isAfter(until)) {
      throw StateError('probe-wait-timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

const host = String.fromEnvironment(
  'C08_EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
Future<void> transport(bool online) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://$host:18089/network'),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'online': online}));
    final response = await request.close();
    check(
      response.statusCode == 200,
      online ? 'transport-restored' : 'transport-cut',
    );
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}

Future<bool> cacheMissing(DocumentReference<Map<String, dynamic>> ref) async {
  try {
    return !(await ref.get(const GetOptions(source: Source.cache))).exists;
  } on FirebaseException catch (error) {
    if (error.code == 'unavailable') return true;
    rethrow;
  }
}

TransactionModel row(String id) => TransactionModel(
  id: id,
  category: 'Gaji',
  description: 'C08 synthetic fixture',
  amount: 100,
  isIncome: true,
  date: DateTime.utc(2026, 11, 27),
);

/// Hold only the result AFTER the real write has committed. Never claim that
/// logout cancels a request or that this is network packet-loss injection.
class HeldAck implements TransactionRepository {
  HeldAck(this.inner);
  final TransactionRepository inner;
  Completer<void>? committed;
  Completer<void>? release;
  @override
  String newId(String uid) => inner.newId(uid);
  @override
  Stream<TransactionSnapshot> watch(String uid) => inner.watch(uid);
  @override
  Future<void> add(String uid, TransactionModel transaction) async {
    await inner.add(uid, transaction);
    final gate = release;
    if (gate != null) {
      release = null;
      committed!.complete();
      await gate.future;
    }
  }

  @override
  Future<void> update(String uid, String id, TransactionModel transaction) =>
      inner.update(uid, id, transaction);
  @override
  Future<void> delete(
    String uid,
    String id, {
    RecordVersion? expectedVersion,
  }) => inner.delete(uid, id, expectedVersion: expectedVersion);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('C08_NATIVE_TEST')) {
    throw StateError('probe-opt-in-required');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('C08 session SDK probe'))),
    ),
  );
  try {
    await probe();
  } catch (error) {
    debugPrint(
      'C08_NATIVE_FAIL ${error is FirebaseException ? error.code : error.runtimeType}',
    );
    if (error is StateError) debugPrint('C08_NATIVE_ASSERT ${error.message}');
  }
}

Future<void> probe() async {
  check(['10.0.2.2', '127.0.0.1'].contains(host), 'loopback-target');
  final app = await Firebase.initializeApp(
    name: defaultFirebaseAppName,
    demoProjectId: 'demo-simanja-c08',
  );
  check(app.options.projectId == 'demo-simanja-c08', 'demo-project');
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9098);
  final db = FirebaseFirestore.instanceFor(app: app);
  final checkpoint = File(
    '${(await getApplicationSupportDirectory()).path}/c08-checkpoint.json',
  );
  final saved = await checkpoint.exists()
      ? jsonDecode(await checkpoint.readAsString()) as Map<String, dynamic>
      : null;
  final phase = saved?['phase'] as String? ?? 'legacy';
  debugPrint('C08_NATIVE_PHASE $phase');
  if (phase == 'legacy') {
    // Fixture simulates an older APK; this is NOT the new runtime policy.
    db.settings = const Settings(persistenceEnabled: true);
  } else {
    FirestoreCachePolicy.configure(db);
    check(db.settings.persistenceEnabled == false, 'production-memory-only');
  }
  db.useFirestoreEmulator(host, 18088);
  final real = FirestoreTransactionRepository(db);
  const password = 'C08-Fixture-Password123!';
  final temp = await getTemporaryDirectory();

  if (phase == 'legacy') {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final email = 'c08-a-$nonce@example.test';
    final user = (await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    )).user!;
    await FirestoreProfileRepository(db).loadOrCreate(user.uid, email);
    await real.add(user.uid, row('legacy-A'));
    final ref = db
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .doc('legacy-A');
    // A committed transaction is not proof that an unread document is cached.
    await ref
        .snapshots(includeMetadataChanges: true)
        .firstWhere((value) => value.exists && !value.metadata.isFromCache)
        .timeout(const Duration(seconds: 40));
    check(
      (await ref.get(const GetOptions(source: Source.cache))).exists,
      'legacy-disk-client-seeded',
    );
    final oldCsv = await File(
      '${temp.path}/simanja_transaksi_Semua_1760000000000_0.csv',
    ).writeAsString('synthetic old CSV');
    final oldDirectory = await Directory(
      '${temp.path}/simanja_exports/csv-previous-process',
    ).create(recursive: true);
    await File('${oldDirectory.path}/old.csv')
        .writeAsString('synthetic old CSV');
    final photo = await File('${temp.path}/c08-source-photo.jpg')
        .writeAsString('synthetic source photo');
    await checkpoint.writeAsString(
      jsonEncode({
        'phase': 'memory',
        'uid': user.uid,
        'email': email,
        'oldCsv': oldCsv.path,
        'oldDirectory': oldDirectory.path,
        'photo': photo.path,
      }),
      flush: true,
    );
    debugPrint('C08_NATIVE_LEGACY_READY');
    return;
  }

  final user = await auth.authStateChanges().first;
  check(
    user != null && user.uid == saved!['uid'],
    'auth-restored-independently-of-firestore-cache',
  );
  final uid = user!.uid;
  final ref = db
      .collection('users')
      .doc(uid)
      .collection('transactions')
      .doc('legacy-A');
  await SessionExportStore.instance.prepare();
  check(
    !await File(saved!['oldCsv']).exists() &&
        !await Directory(saved['oldDirectory']).exists(),
    'previous-process-exports-pruned',
  );
  check(await File(saved['photo']).exists(), 'source-photo-not-deleted');
  await transport(false);
  await db.disableNetwork();
  check(
    await cacheMissing(ref),
    'cold-memory-client-does-not-read-legacy-disk',
  );
  final state = AppState.instance;
  final held = HeldAck(real);
  state.useProfileRepository(FirestoreProfileRepository(db));
  state.useTransactionRepository(held);
  await state.beginSession(uid, user.email!);
  check(
    !state.profileReady &&
        state.profileError != null &&
        state.transactions.isEmpty,
    'offline-restart-not-ready-and-no-old-user-data',
  );
  await transport(true);
  await db.enableNetwork();
  // Confirm actual server stream rather than treating enableNetwork as an ack.
  await ref
      .snapshots(includeMetadataChanges: true)
      .firstWhere((value) => !value.metadata.isFromCache)
      .timeout(const Duration(seconds: 40));
  await state.retryProfile();
  await waitFor(() => state.transactionsServerConfirmed);

  if (phase == 'reset') {
    check(state.transactions.isEmpty, 'post-reset-restart-no-ghost-records');
    check(
      !await File(saved['leftover']).exists(),
      'cold-process-export-cleanup',
    );
    check(
      await File(saved['photo']).exists(),
      'cold-process-source-photo-retained',
    );
    check(
      state.profileReady && state.pendingMutations == 0,
      'fresh-profile-no-pending-replay',
    );
    await state.clearSession();
    await auth.signOut();
    debugPrint('C08_NATIVE_PASS');
    return;
  }

  check(
    state.transactions.length == 1 &&
        state.transactions.single.id == 'legacy-A',
    'online-A-complete-own-data',
  );
  final leaseA = state.exportLease;
  final fileA = (await leaseA.write(
    CsvExporter.encode(state.transactions, 'C08'),
    'a.csv',
  ))!;
  state.updatePhoto(saved['photo']);
  held.committed = Completer<void>();
  final release = Completer<void>();
  held.release = release;
  var staleRejected = false;
  final oldWrite = state
      .addTransaction(row('held-A'))
      .then<void>(
        (_) => throw StateError('old-session-write-returned-success'),
        onError: (Object _) {
          staleRejected = true;
        },
      );
  await held.committed!.future;
  check(state.hasInFlightDataWrites, 'A-write-result-still-pending');
  check(await state.clearSession(), 'A-managed-file-cleanup-completed');
  await auth.signOut();
  check(
    !leaseA.isActive && !await fileA.exists() && state.photoPath == null,
    'A-ui-and-export-lease-invalidated',
  );
  check(await File(saved['photo']).exists(), 'original-photo-survives-logout');
  final userB = (await auth.createUserWithEmailAndPassword(
    email: 'c08-b-${DateTime.now().microsecondsSinceEpoch}@example.test',
    password: password,
  )).user!;
  await state.beginSession(userB.uid, userB.email!);
  await waitFor(() => state.transactionsServerConfirmed);
  check(state.transactions.isEmpty, 'B-never-shows-A');
  await state.addTransaction(row('only-B'));
  await waitFor(() => state.transactions.length == 1);
  final fileB = (await state.exportLease.write([1], 'b.csv'))!;
  // SDK cache is NOT an Auth boundary; AppState/repository owner paths are.
  // Unlistened documents can already be evicted by the memory cache. Neither
  // their presence nor their absence defines the current UI account.
  debugPrint(
    'C08_NATIVE_RAW_CACHE ${await cacheMissing(ref) ? 'missing' : 'retained'}',
  );
  check(
    state.sessionUid == userB.uid && state.transactions.single.id == 'only-B',
    'B-owner-isolation-independent-of-raw-cache-retention',
  );
  release.complete();
  await oldWrite;
  check(
    staleRejected &&
        state.sessionUid == userB.uid &&
        state.pendingMutations == 0 &&
        state.transactions.single.id == 'only-B' &&
        await fileB.exists(),
    'late-A-result-cannot-settle-or-delete-B-data',
  );
  await state.clearSession();
  await auth.signOut();
  await auth.signInWithEmailAndPassword(
    email: saved['email'],
    password: password,
  );
  await state.beginSession(uid, saved['email']);
  await waitFor(
    () => state.transactionsServerConfirmed && state.transactions.length == 2,
  );
  check(
    state.transactions.any((row) => row.id == 'held-A') &&
        !state.transactions.any((row) => row.id == 'only-B'),
    'A-return-owns-committed-write-not-canceled-by-logout',
  );
  state.suspendSessionData();
  await state.beginSession(uid, saved['email']);
  await state.retryTransactions();
  await state.retryProfile();
  check(
    state.dataAccessSuspended &&
        !state.profileReady &&
        state.transactions.isEmpty &&
        !state.reportSource.canExport,
    'deleting-hook-blocks-data-retry-and-export',
  );
  var writeBlocked = false;
  try {
    await state.addTransaction(row('must-not-write'));
  } on StateError {
    writeBlocked = true;
  }
  check(writeBlocked, 'deleting-hook-blocks-new-writes');
  await state.resumeSessionData(uid, saved['email']);
  await waitFor(
    () => state.transactionsServerConfirmed && state.transactions.length == 2,
  );
  check(!state.dataAccessSuspended, 'explicit-confirmed-active-resume');
  final leftover = (await state.exportLease.write([1], 'restart.csv'))!;
  await checkpoint.writeAsString(
    jsonEncode({...saved, 'phase': 'reset', 'leftover': leftover.path}),
    flush: true,
  );
  debugPrint('C08_NATIVE_RESET_READY');
  // Operator resets ONLY the owned demo Firestore emulator via localhost API.
  await waitFor(
    () => state.transactionsServerConfirmed && state.transactions.isEmpty,
  );
  check(state.transactions.isEmpty, 'live-emulator-reset-removes-old-snapshot');
  debugPrint('C08_NATIVE_RESTART_READY');
}
