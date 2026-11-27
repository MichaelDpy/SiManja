import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

import 'support/memory_history.dart';
import 'support/memory_profiles.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
Future<void> saveName(AppState state, String name) => state.updateProfile(
  newName: name,
  newEmail: state.email,
  newPhone: '',
  newAddress: '',
  newCity: '',
  newJob: '',
  newIncome: 0,
);

void main() {
  late AppState state;
  late MemoryProfiles profiles;
  late MemoryHistory transactions;
  setUp(() async {
    profiles = MemoryProfiles();
    transactions = MemoryHistory()
      ..rows['A'] = reportFixture(3)
      ..rows['B'] = reportFixture(1);
    state = AppState.forTesting(profiles: profiles, transactions: transactions);
    await state.beginSession('A', 'a@example.test');
    await tick();
  });
  tearDown(() => state.dispose());

  test(
    'A logout B A has fresh revisions, profiles, listeners and file leases',
    () async {
      final revision = state.sessionRevision;
      final files = state.exportLease;
      state.updatePhoto('source-photo');
      await state.clearSession();
      expect(files.isActive, isFalse);
      expect(state.transactions, isEmpty);
      expect(state.photoPath, isNull);
      await state.beginSession('B', 'b@example.test');
      await tick();
      expect(state.transactions, hasLength(1));
      expect(transactions.subscriptions['A'], 0);
      expect(transactions.subscriptions['B'], 1);
      await state.clearSession();
      await state.beginSession('A', 'a@example.test');
      await tick();
      expect(state.transactions, hasLength(3));
      expect(state.sessionRevision, greaterThan(revision));
      expect(state.exportLease, isNot(same(files)));
    },
  );

  test(
    'same UID repository replacement cannot apply delayed profile load/error',
    () async {
      final delayed = Completer<UserProfile>();
      profiles.delayedLoads['A'] = delayed;
      await state.clearSession();
      final old = state.beginSession('A', 'a@example.test');
      final replacement = MemoryProfiles()
        ..profiles['A'] = UserProfile.initial('new@example.test');
      state.useProfileRepository(replacement);
      await state.beginSession('A', 'a@example.test');
      delayed.completeError(StateError('old sensitive error'));
      await old;
      await tick();
      expect(state.name, 'new');
      expect(state.profileError, isNull);
      expect(state.profileReady, isTrue);
    },
  );

  test(
    'old profile save cannot clear the new repository saving flag',
    () async {
      profiles.pendingSave = Completer<void>();
      final old = saveName(state, 'old');
      final rejected = expectLater(old, throwsStateError);
      final replacement = MemoryProfiles();
      state.useProfileRepository(replacement);
      await state.beginSession('A', 'a@example.test');
      replacement.pendingSave = Completer<void>();
      final current = saveName(state, 'current');
      profiles.pendingSave!.complete();
      await rejected;
      expect(state.profileSaving, isTrue);
      expect(state.profileWriteFailure, isNull);
      replacement.pendingSave!.complete();
      await current;
      expect(state.name, 'current');
    },
  );

  test('transaction rebind clears confirmed data; old write cannot settle new write', () async {
    transactions.pendingWrite = Completer<void>();
    final draft = TransactionModel(
      id: 'new-shared-id',
      category: 'Gaji',
      description: 'new request',
      amount: 1,
      isIncome: true,
      date: DateTime.utc(2026, 11, 27),
    );
    final old = state.addTransaction(
      draft.copyWith(description: 'old request'),
    );
    final rejected = expectLater(old, throwsStateError);
    final replacement = MemoryHistory();
    state.useTransactionRepository(replacement);
    expect(state.transactions, isEmpty);
    expect(state.transactionsServerConfirmed, isFalse);
    expect(state.reportSource.canExport, isFalse);
    await state.retryTransactions();
    await tick();
    replacement.pendingWrite = Completer<void>();
    final current = state.addTransaction(draft);
    transactions.pendingWrite!.complete();
    await rejected;
    expect(state.pendingMutations, 1);
    expect(state.transactionWriteFailure, isNull);
    replacement.pendingWrite!.complete();
    await current;
    await tick();
    expect(state.pendingMutations, 0);
    expect(state.transactions, hasLength(1));
  });

  test(
    'queued stream errors and profile results from A do not reach B',
    () async {
      transactions.events['A']!.addError(const FormatException('A private'));
      await state.clearSession();
      await state.beginSession('B', 'b@example.test');
      await tick();
      expect(state.transactionsError, isNull);
      expect(state.transactions, hasLength(1));
      expect(state.email, 'b@example.test');
    },
  );

  test(
    'deleting hook prevents retry, writes, export and queued resurrection',
    () async {
      final oldFiles = state.exportLease;
      transactions.events['A']!.add(TransactionSnapshot(reportFixture(10)));
      state.suspendSessionData();
      await tick();
      expect(state.dataAccessSuspended, isTrue);
      expect(state.transactions, isEmpty);
      expect(oldFiles.isActive, isFalse);
      await state.beginSession('A', 'a@example.test');
      await state.retryTransactions();
      await state.retryProfile();
      expect(state.profileReady, isFalse);
      expect(state.reportSource.canExport, isFalse);
      expect(() => state.generateId(), throwsStateError);
      await expectLater(
        state.addTransaction(reportFixture(1).single),
        throwsStateError,
      );
      expect(
        () => state.resumeSessionData('B', 'b@example.test'),
        throwsStateError,
      );
      await state.resumeSessionData('A', 'a@example.test');
      await tick();
      expect(state.transactions, hasLength(3));
      expect(state.profileReady, isTrue);
      expect(state.dataAccessSuspended, isFalse);
    },
  );
}
