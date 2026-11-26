import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/sync_failure.dart';
import 'package:simanja/repositories/record_concurrency.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/widgets/transaction_sync_status.dart';

import 'support/memory_transactions.dart';
import 'support/memory_profiles.dart';

TransactionModel row() => TransactionModel(
  id: 'stable',
  category: 'Gaji',
  description: 'Draft',
  amount: 100,
  isIncome: true,
  date: DateTime.utc(2026, 1, 1),
);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('failure memisahkan penolakan izin dari hasil tidak pasti tanpa pesan SDK privat', () {
    for (final code in [
      'permission-denied',
      'unauthenticated',
      'unavailable',
      'deadline-exceeded',
    ]) {
      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message: 'private/uid/secret',
      );
      final failure = SyncFailure.from(error);
      expect(
        failure.mayHaveCommitted,
        !['permission-denied', 'unauthenticated'].contains(code),
      );
      expect(failure.toString(), isNot(contains('private/uid')));
      expect(
        SyncFailure.from(error, forceUnconfirmed: true).mayHaveCommitted,
        isTrue,
      );
    }
    expect(
      SyncFailure.from(TimeoutException('private')).kind,
      SyncFailureKind.timeout,
    );
  });
  test('request pending, snapshot lokal dan konfirmasi server adalah state berbeda', () async {
    final repo = MemoryTransactions()..emitInitial = false;
    final state = AppState.forTesting(transactions: repo);
    addTearDown(state.dispose);
    await state.beginSession('A', 'a@example.com');
    expect(state.transactionsServerConfirmed, isFalse);
    repo.emit('A', [row()], cache: true);
    await tick();
    expect(state.transactionsServerConfirmed, isFalse);
    repo.emit('A', [row()], pending: true);
    await tick();
    expect(state.transactionsServerConfirmed, isFalse);
    expect(state.pendingMutations, 0);
    repo.emit('A', [row()]);
    await tick();
    expect(state.transactionsServerConfirmed, isTrue);
    repo.pendingWrite = Completer<void>();
    var completed = false;
    final request = state
        .updateTransaction('stable', row())
        .then((_) => completed = true);
    await tick();
    expect(state.pendingMutations, 1);
    expect(completed, isFalse);
    repo.pendingWrite!.complete();
    await request;
    expect(completed, isTrue);
  });
  test('lost ack sesudah commit: hasil tidak pasti dan retry ID sama tidak menduplikasi', () async {
    final repo = MemoryTransactions()
      ..failureAfterCommit = TimeoutException('lost ack');
    final state = AppState.forTesting(transactions: repo);
    addTearDown(state.dispose);
    await state.beginSession('A', 'a@example.com');
    await tick();
    await expectLater(state.addTransaction(row()), throwsA(isA<SyncFailure>()));
    await tick();
    expect(state.transactionWriteFailure!.mayHaveCommitted, isTrue);
    expect(repo.rows['A'], hasLength(1));
    await state.addTransaction(row());
    await tick();
    expect(repo.rows['A'], hasLength(1));
    expect(repo.committedWrites, 1);
    expect(state.transactionWriteFailure, isNull);
  });
  test(
    'restart tidak membuat antrean atau replay otomatis dari kegagalan',
    () async {
      final repo = MemoryTransactions()
        ..writeFailure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        );
      final state = AppState.forTesting(transactions: repo);
      await state.beginSession('A', 'a@example.com');
      await expectLater(
        state.addTransaction(row()),
        throwsA(isA<SyncFailure>()),
      );
      state.dispose();
      repo.writeFailure = null;
      final reopened = AppState.forTesting(transactions: repo);
      addTearDown(reopened.dispose);
      await reopened.beginSession('A', 'a@example.com');
      await tick();
      expect(repo.writes, 1);
      expect(repo.rows['A'] ?? [], isEmpty);
      expect(reopened.transactionWriteFailure, isNull);
      expect(reopened.pendingMutations, 0);
    },
  );
  test('profil ditolak menjaga snapshot; read gagal sesudah commit tetap unconfirmed', () async {
    final profiles = MemoryProfiles();
    final state = AppState.forTesting(profiles: profiles);
    addTearDown(state.dispose);
    await state.beginSession('A', 'a@example.com');
    profiles.saveFailure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(state.setDarkMode(false), throwsA(isA<SyncFailure>()));
    expect(state.darkMode, isTrue);
    expect(state.profileWriteFailure!.mayHaveCommitted, isFalse);
    profiles.saveFailure = SyncFailure.from(
      profiles.saveFailure!,
      forceUnconfirmed: true,
    );
    await expectLater(state.setDarkMode(false), throwsA(isA<SyncFailure>()));
    expect(state.profileWriteFailure!.mayHaveCommitted, isTrue);
    expect(state.profileSaving, isFalse);
  });
  test(
    'reconcile hanya untuk payload, incarnation, schema dan revision tepat',
    () {
      final payload = TransactionMapper.toMap(row());
      final current = <String, dynamic>{
        ...payload,
        'revision': 1,
        'createdAt': Timestamp(100, 0),
        'updatedAt': Timestamp(100, 0),
      };
      expect(
        RecordConcurrency.confirmsRetry(desired: payload, current: current),
        isTrue,
      );
      expect(
        RecordConcurrency.confirmsRetry(
          desired: payload,
          current: {...current, 'amount': 200},
        ),
        isFalse,
      );
      expect(
        RecordConcurrency.confirmsRetry(
          desired: payload,
          current: {...current, 'amount': 100.0},
        ),
        isFalse,
      );
      final base = RecordConcurrency.read(current)!;
      final next = {...current, 'revision': 2, 'updatedAt': Timestamp(101, 0)};
      expect(
        RecordConcurrency.confirmsRetry(
          desired: payload,
          current: next,
          expected: base,
        ),
        isTrue,
      );
      expect(
        RecordConcurrency.confirmsRetry(
          desired: payload,
          current: {...next, 'revision': 3},
          expected: base,
        ),
        isFalse,
      );
      expect(
        RecordConcurrency.confirmsRetry(
          desired: payload,
          current: {...next, 'createdAt': Timestamp(102, 0)},
          expected: base,
        ),
        isFalse,
      );
      final legacy = {...payload}..remove('dateVersion');
      expect(
        RecordConcurrency.confirmsRetry(
          desired: legacy,
          current: next,
          expected: base,
        ),
        isFalse,
      );
    },
  );
  testWidgets(
    'status local pending bukan request; Muat data tidak mengulang write',
    (tester) async {
      final repo = MemoryTransactions();
      final state = AppState.forTesting(transactions: repo);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
      await state.beginSession('A', 'a@example.com');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TransactionSyncStatus(state: state)),
        ),
      );
      repo.emit('A', [row()], cache: true, pending: true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Data lokal belum dikonfirmasi'),
        findsOneWidget,
      );
      expect(find.textContaining('Permintaan sedang berjalan'), findsNothing);
      repo.writeFailure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await expectLater(
        state.addTransaction(row()),
        throwsA(isA<SyncFailure>()),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Perubahan ditolak karena izin akun'),
        findsOneWidget,
      );
      final attempts = repo.writes;
      await tester.tap(find.text('Muat data'));
      await tester.pumpAndSettle();
      expect(repo.writes, attempts);
      expect(
        find.textContaining('Perubahan ditolak karena izin akun'),
        findsOneWidget,
      );
      await tester.tap(find.text('Tutup pesan'));
      await tester.pumpAndSettle();
      expect(state.transactionWriteFailure, isNull);
    },
  );
}
