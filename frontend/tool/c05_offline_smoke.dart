// Emulator-only probe. Run from a separate temporary Android app that depends
// on simanja by path, with --dart-define=C05_NATIVE_TEST=true. Never use the
// SIMANJA application ID. Restart that test app once after RESTART_READY.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/models/sync_failure.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/profile_repository.dart';
import 'package:simanja/repositories/transaction_repository.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  debugPrint('C05_NATIVE_CHECK $label');
}

Future<void> rejectedOffline(
  Future<void> Function() request,
  String label,
) async {
  var rejected = false;
  try {
    await request();
  } on FirebaseException catch (error) {
    rejected = true;
    check(
      ['unavailable', 'deadline-exceeded'].contains(error.code),
      '$label-code',
    );
  }
  check(rejected, label);
}

// Control only the loopback TCP proxy used by this separate QA package.
Future<void> transport(bool online) async {
  const host = String.fromEnvironment(
    'C05_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://$host:18081/network'),
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

TransactionModel draft(String id, {double amount = 100}) => TransactionModel(
  id: id,
  category: 'Gaji',
  description: 'C05 synthetic fixture',
  amount: amount,
  isIncome: true,
  date: DateTime.utc(2026, 1, 1),
);

/// Deliberate loss of the result AFTER the real repository commits. This is
/// fault injection at the consumer boundary, not a claim of packet-level loss.
class DropOneAck implements TransactionRepository {
  DropOneAck(this.inner);
  final TransactionRepository inner;
  String? operation;
  void drop(String kind) {
    if (operation != kind) return;
    operation = null;
    throw TimeoutException('synthetic lost result after commit');
  }

  @override
  String newId(String uid) => inner.newId(uid);
  @override
  Stream<TransactionSnapshot> watch(String uid) => inner.watch(uid);
  @override
  Future<void> add(String uid, TransactionModel tx) async {
    await inner.add(uid, tx);
    drop('add');
  }

  @override
  Future<void> update(String uid, String id, TransactionModel tx) async {
    await inner.update(uid, id, tx);
    drop('update');
  }

  @override
  Future<void> delete(
    String uid,
    String id, {
    RecordVersion? expectedVersion,
  }) async {
    await inner.delete(uid, id, expectedVersion: expectedVersion);
    drop('delete');
  }
}

Future<void> waitFor(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) {
      throw StateError('confirmation-wait-expired');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// enableNetwork resumes transport but does not itself acknowledge fresh data.
Future<void> serverReady(DocumentReference<Map<String, dynamic>> ref) async {
  var confirmed = false;
  Object? failure;
  final subscription = ref.snapshots(includeMetadataChanges: true).listen((
    snapshot,
  ) {
    confirmed =
        !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites;
  }, onError: (Object error) => failure = error);
  try {
    await waitFor(() => confirmed || failure != null);
    if (failure != null) throw failure!;
    check(confirmed, 'server-transport-ready');
  } finally {
    await subscription.cancel();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('C05_NATIVE_TEST')) {
    throw StateError('emulator-probe-opt-in-required');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('C05 emulator SDK probe'))),
    ),
  );
  try {
    await probe();
  } catch (error) {
    // Fixtures only; still avoid dumping SDK messages or auth payloads.
    debugPrint(
      'C05_NATIVE_FAIL ${error is FirebaseException ? error.code : error.runtimeType}',
    );
    if (error is StateError) debugPrint('C05_NATIVE_ASSERT ${error.message}');
  }
}

Future<void> probe() async {
  final app = await Firebase.initializeApp(
    name: defaultFirebaseAppName,
    demoProjectId: 'demo-simanja',
  );
  check(app.options.projectId == 'demo-simanja', 'demo-project');
  const host = String.fromEnvironment(
    'C05_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  check(['10.0.2.2', '127.0.0.1'].contains(host), 'loopback-target');
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  final db = FirebaseFirestore.instanceFor(app: app);
  db.useFirestoreEmulator(host, 18080);
  final transactions = FirestoreTransactionRepository(db);
  final profiles = FirestoreProfileRepository(db);
  final directory = await getApplicationSupportDirectory();
  final checkpoint = File('${directory.path}/c05-native-checkpoint.json');
  final restarting = await checkpoint.exists();

  if (!restarting) {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final user = (await auth.createUserWithEmailAndPassword(
      email: 'c05-$nonce@example.test',
      password: 'C05-fixture-Password123!',
    )).user!;
    final uid = user.uid;
    final profile = await profiles.loadOrCreate(uid, user.email!);
    final collection = db
        .collection('users')
        .doc(uid)
        .collection('transactions');
    await transactions.add(uid, draft('kept'));
    final stored = await collection
        .doc('kept')
        .get(const GetOptions(source: Source.server));
    final baseline = TransactionMapper.fromMap('kept', stored.data()!);
    await transport(false);
    await db.disableNetwork();
    final cached = await collection
        .doc('kept')
        .get(const GetOptions(source: Source.cache));
    check(
      cached.exists && cached.metadata.isFromCache,
      'native-offline-cache-readable',
    );
    await rejectedOffline(
      () => transactions.add(uid, draft('offline-create')),
      'create-offline-rejected',
    );
    await rejectedOffline(
      () => transactions.update(uid, 'kept', baseline.copyWith(amount: 999)),
      'update-offline-rejected',
    );
    await rejectedOffline(
      () => transactions.delete(uid, 'kept', expectedVersion: baseline.version),
      'delete-offline-rejected',
    );
    await rejectedOffline(() async {
      await profiles.save(
        uid,
        profile.copyWith(name: 'Offline draft'),
        previous: profile,
      );
    }, 'profile-offline-rejected');
    await transport(true);
    await db.enableNetwork();
    await serverReady(collection.doc('kept'));
    check(
      !(await collection
              .doc('offline-create')
              .get(const GetOptions(source: Source.server)))
          .exists,
      'no-offline-create-replay',
    );
    final kept =
        (await collection
                .doc('kept')
                .get(const GetOptions(source: Source.server)))
            .data()!;
    check(
      kept['amount'] == 100 && kept['revision'] == 1,
      'no-offline-update-delete-replay',
    );

    final lost = DropOneAck(transactions);
    final state = AppState.instance;
    state.useProfileRepository(profiles);
    state.useTransactionRepository(lost);
    await state.beginSession(uid, user.email!);
    lost.operation = 'add';
    try {
      await state.addTransaction(draft('ack'));
    } on SyncFailure catch (failure) {
      check(failure.mayHaveCommitted, 'add-lost-ack-unconfirmed');
    }
    check(
      state.transactionWriteFailure != null,
      'add-future-not-false-success',
    );
    await state.addTransaction(draft('ack'));
    var ack = await collection
        .doc('ack')
        .get(const GetOptions(source: Source.server));
    check(ack.data()!['revision'] == 1, 'create-retry-no-second-write');
    final old = TransactionMapper.fromMap('ack', ack.data()!);
    final changed = old.copyWith(amount: 222);
    lost.operation = 'update';
    try {
      await state.updateTransaction('ack', changed);
    } on SyncFailure catch (failure) {
      check(failure.mayHaveCommitted, 'update-lost-ack-unconfirmed');
    }
    ack = await collection
        .doc('ack')
        .get(const GetOptions(source: Source.server));
    final updatedAt = ack.data()!['updatedAt'];
    await state.updateTransaction('ack', changed);
    ack = await collection
        .doc('ack')
        .get(const GetOptions(source: Source.server));
    check(
      ack.data()!['revision'] == 2 && ack.data()!['updatedAt'] == updatedAt,
      'update-retry-no-second-write',
    );
    final toDelete = TransactionMapper.fromMap('ack', ack.data()!);
    lost.operation = 'delete';
    try {
      await state.deleteTransaction('ack', previous: toDelete);
    } on SyncFailure catch (failure) {
      check(failure.mayHaveCommitted, 'delete-lost-ack-unconfirmed');
    }
    await state.deleteTransaction('ack', previous: toDelete);
    check(
      !(await collection
              .doc('ack')
              .get(const GetOptions(source: Source.server)))
          .exists,
      'delete-retry-absent',
    );
    var denied = false;
    try {
      await transactions.add('not-owned-c05', draft('denied'));
    } on FirebaseException catch (error) {
      final failure = SyncFailure.from(error);
      denied =
          failure.kind == SyncFailureKind.permissionDenied &&
          !failure.mayHaveCommitted;
    }
    check(denied, 'permission-denied-definitive');
    final desiredProfile = profile.copyWith(name: 'C05 confirmed');
    final confirmed = await profiles.save(
      uid,
      desiredProfile,
      previous: profile,
    );
    final retried = await profiles.save(uid, desiredProfile, previous: profile);
    check(
      confirmed.version == retried.version,
      'profile-retry-no-second-write',
    );
    state.clearSession();
    await checkpoint.writeAsString(jsonEncode({'uid': uid}), flush: true);
    debugPrint('C05_NATIVE_RESTART_READY');
    return;
  }

  final expectedUid = (jsonDecode(
    await checkpoint.readAsString(),
  ) as Map<String, dynamic>)['uid'];
  final user = await auth.authStateChanges().first;
  check(
    user != null && user.uid == expectedUid,
    'auth-restored-after-process-restart',
  );
  final uid = user!.uid;
  final collection = db.collection('users').doc(uid).collection('transactions');
  await transport(false);
  await db.disableNetwork();
  final cached = await collection
      .doc('kept')
      .get(const GetOptions(source: Source.cache));
  check(
    cached.exists && cached.metadata.isFromCache,
    'disk-cache-after-process-restart',
  );
  final reopened = AppState.instance;
  reopened.useProfileRepository(profiles);
  reopened.useTransactionRepository(transactions);
  await reopened.beginSession(uid, user.email!);
  check(
    !reopened.profileReady &&
        reopened.profileError != null &&
        !reopened.transactionsServerConfirmed,
    'offline-restart-not-false-ready',
  );
  check(reopened.pendingMutations == 0, 'restart-no-custom-write-queue');
  await transport(true);
  await db.enableNetwork();
  await serverReady(collection.doc('kept'));
  await reopened.retryProfile();
  await waitFor(() => reopened.transactionsServerConfirmed);
  check(
    reopened.profileReady && reopened.transactions.single.id == 'kept',
    'reconnect-server-confirmed',
  );
  final stored = await collection
      .doc('kept')
      .get(const GetOptions(source: Source.server));
  check(
    stored.data()!['revision'] == 1 && stored.data()!['amount'] == 100,
    'restart-no-mutation-replay',
  );
  check(
    !(await collection
            .doc('offline-create')
            .get(const GetOptions(source: Source.server)))
        .exists,
    'restart-offline-create-still-absent',
  );
  reopened.clearSession();
  debugPrint('C05_NATIVE_PASS');
}
