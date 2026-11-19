import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/repositories/transaction_repository.dart';

import 'support/memory_transactions.dart';
import 'support/memory_profiles.dart';

TransactionModel tx(
  String id, {
  double amount = 1000,
  bool income = true,
  int day = 1,
}) => TransactionModel(
  id: id,
  category: income ? 'Gaji' : 'Belanja',
  description: 'Data $id',
  amount: amount,
  isIncome: income,
  date: DateTime(2026, 11, day),
);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  late MemoryTransactions repository;
  late AppState state;
  setUp(() {
    repository = MemoryTransactions();
    state = AppState.forTesting(transactions: repository);
  });
  tearDown(() => state.dispose());

  test(
    'tidak berlangganan sebelum profil siap dan abaikan profil sesi lama',
    () async {
      final profiles = MemoryProfiles();
      final delayed = Completer<UserProfile>();
      profiles.delayedLoads['A'] = delayed;
      state.dispose();
      state = AppState.forTesting(profiles: profiles, transactions: repository);
      final oldSession = state.beginSession('A', 'a@example.com');
      expect(state.profileLoading, isTrue);
      expect(repository.subscriptions, isEmpty);
      await expectLater(
        state.addTransaction(tx('too-early')),
        throwsStateError,
      );
      state.clearSession();
      await state.beginSession('B', 'b@example.com');
      await tick();
      delayed.complete(UserProfile.initial('a@example.com'));
      await oldSession;
      await tick();
      expect(repository.subscriptions.containsKey('A'), isFalse);
      expect(repository.subscriptions['B'], 1);
      expect(state.sessionUid, 'B');
    },
  );

  test(
    'stream dimulai setelah profil siap, daftar diurutkan dan immutable',
    () async {
      repository.emitInitial = false;
      await state.beginSession('A', 'a@example.com');
      expect(state.transactionsLoading, isTrue);
      expect(state.transactions, isEmpty);
      repository.emit('A', [tx('old'), tx('new', day: 2)], cache: true);
      await tick();
      expect(state.transactions.map((item) => item.id), ['new', 'old']);
      expect(state.transactionsFromCache, isTrue);
      expect(state.transactionsLoading, isFalse);
      expect(() => state.transactions.clear(), throwsUnsupportedError);
    },
  );
  test(
    'CRUD menggunakan repository dan stream memperbarui ringkasan',
    () async {
      await state.beginSession('A', 'a@example.com');
      await tick();
      final id = state.generateId();
      expect(id, startsWith('generated-A-'));
      await state.addTransaction(tx(id));
      await tick();
      expect(state.totalIncome, 1000);
      await state.updateTransaction(id, tx(id, amount: 400, income: false));
      await tick();
      expect(state.totalIncome, 0);
      expect(state.totalExpense, 400);
      await state.deleteTransaction(id);
      await tick();
      expect(state.transactions, isEmpty);
      expect(repository.writes, 3);
    },
  );
  test(
    'write tertunda tidak sukses palsu dan submit ID sama diblokir',
    () async {
      await state.beginSession('A', 'a@example.com');
      await tick();
      repository.pendingWrite = Completer<void>();
      final request = state.addTransaction(tx('same'));
      expect(state.pendingMutations, 1);
      expect(state.transactions, isEmpty);
      await expectLater(state.addTransaction(tx('same')), throwsStateError);
      expect(repository.writes, 1);
      repository.writeFailure = StateError('denied');
      final rejected = expectLater(request, throwsStateError);
      repository.pendingWrite!.complete();
      await rejected;
      expect(state.pendingMutations, 0);
      expect(state.transactions, isEmpty);
    },
  );
  test('snapshot error dapat di-retry tanpa mengisi fixture dan satu langganan aktif', () async {
    await state.beginSession('A', 'a@example.com');
    await tick();
    repository.events['A']!.addError(const FormatException('invalid'));
    await tick();
    expect(state.transactionsError, contains('tidak valid'));
    expect(state.transactionsLoading, isFalse);
    await state.retryTransactions();
    await tick();
    expect(state.transactionsError, isNull);
    expect(state.transactions, isEmpty);
    expect(repository.subscriptions['A'], 1);
    await state.beginSession('A', 'a@example.com');
    await tick();
    expect(repository.subscriptions['A'], 1);
  });
  test(
    'event yang sudah diantrekan langganan lama diabaikan setelah retry',
    () async {
      await state.beginSession('A', 'a@example.com');
      await tick();
      repository.events['A']!.add(TransactionSnapshot([tx('stale')]));
      await state.retryTransactions();
      await tick();
      expect(state.transactions, isEmpty);
    },
  );
  test(
    'UID berubah saat write tertunda tidak mencemari akun berikutnya',
    () async {
      await state.beginSession('A', 'a@example.com');
      await tick();
      repository.pendingWrite = Completer<void>();
      final request = state.addTransaction(tx('private-A'));
      final rejected = expectLater(request, throwsStateError);
      state.clearSession();
      await state.beginSession('B', 'b@example.com');
      await tick();
      repository.pendingWrite!.complete();
      await rejected;
      await tick();
      expect(state.sessionUid, 'B');
      expect(state.transactions, isEmpty);
      expect(state.pendingMutations, 0);
      expect(repository.subscriptions['A'], 0);
      expect(repository.subscriptions['B'], 1);
    },
  );
  test('metadata cache dan pending tidak dianggap konfirmasi server', () async {
    await state.beginSession('A', 'a@example.com');
    await tick();
    repository.emit('A', [tx('cached')], cache: true, pending: true);
    await tick();
    expect(state.transactionsFromCache, isTrue);
    expect(state.transactionsHasPendingWrites, isTrue);
    repository.emit('A', [tx('cached')]);
    await tick();
    expect(state.transactionsFromCache, isFalse);
    expect(state.transactionsHasPendingWrites, isFalse);
  });
  test('state baru memuat transaksi akun dari repository yang sama', () async {
    await state.beginSession('A', 'a@example.com');
    await tick();
    await state.addTransaction(tx('persisted'));
    await tick();
    final reopened = AppState.forTesting(transactions: repository);
    await reopened.beginSession('A', 'a@example.com');
    await tick();
    expect(reopened.transactions.single.id, 'persisted');
    reopened.dispose();
  });
  test(
    'logout dan retry tanpa sesi tetap kosong serta tidak memuat dummy',
    () async {
      await state.beginSession('A', 'a@example.com');
      await tick();
      repository.emit('A', [tx('private-A')]);
      await tick();
      state.clearSession();
      await state.retryTransactions();
      repository.emit('A', [tx('late')]);
      await tick();
      expect(state.transactions, isEmpty);
      expect(state.transactionsFromCache, isFalse);
      expect(repository.subscriptions['A'], 0);
    },
  );
}
