import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/repositories/record_concurrency.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';

Map<String, dynamic> data({int? revision = 1, Timestamp? updated}) => {
  'category': 'Gaji',
  'description': 'Awal',
  'amount': 10,
  'isIncome': true,
  'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
  'dateVersion': 2,
  'revision': ?revision,
  'createdAt': Timestamp(100000, 123456000),
  'updatedAt': updated ?? Timestamp(100000, 123456000),
};

void main() {
  test('versi snapshot bertahan di draft; counter, metadata dan incarnation dibandingkan', () {
    final first = TransactionMapper.fromMap('a', data());
    final draft = first.copyWith(amount: 20);
    expect(draft.version, first.version);
    for (final changed in [
      {...data(), 'revision': 2},
      data(updated: Timestamp(100001, 123456000)),
      {...data(), 'createdAt': Timestamp(100002, 123456000)},
    ]) {
      expect(
        () => RecordConcurrency.requireSame(
          draft.version,
          RecordConcurrency.read(changed),
        ),
        throwsA(
          isA<RecordConflict>().having(
            (e) => e.reason,
            'reason',
            ConflictReason.changed,
          ),
        ),
      );
    }
    RecordConcurrency.requireSame(
      first.version,
      RecordConcurrency.read(data()),
    );
  });

  test(
    'model persisted tidak dapat dikirim sebagai create ulang setelah dihapus',
    () async {
      final repository = FirestoreTransactionRepository.lazy(
        () => throw StateError('SDK tidak boleh dipanggil'),
      );
      await expectLater(
        repository.add('A', TransactionMapper.fromMap('a', data())),
        throwsArgumentError,
      );
    },
  );
  test('legacy revision nol, pending read-only, tipe invalid dan batas versi jelas', () {
    expect(RecordConcurrency.read(data(revision: null))!.revision, 0);
    expect(RecordConcurrency.read({...data(), 'updatedAt': null}), isNull);
    expect(
      () => RecordConcurrency.requireSame(null, RecordConcurrency.read(data())),
      throwsA(isA<RecordConflict>()),
    );
    for (final revision in [null, 0, -1, 1.5, '1', 9007199254740992]) {
      expect(
        () => RecordConcurrency.read({...data(), 'revision': revision}),
        throwsFormatException,
      );
    }
    expect(RecordConcurrency.next(const RecordVersion(0, 'a', 'a')), 1);
    expect(
      () => RecordConcurrency.next(
        const RecordVersion(9007199254740991, 'a', 'a'),
      ),
      throwsA(isA<RecordConflict>()),
    );
  });
  test('profil three-way merge field berbeda, conflict field sama, retry desired sama', () {
    const base = RecordVersion(1, 'created', 'old');
    const latest = RecordVersion(2, 'created', 'new');
    final before = <String, Object>{'name': 'A', 'city': 'Bandung'};
    expect(
      RecordConcurrency.profilePatch(
        before: before,
        desired: {...before, 'name': 'B'},
        current: {...before, 'city': 'Jakarta'},
        expected: base,
        actual: latest,
      ),
      {'name': 'B'},
    );
    expect(
      () => RecordConcurrency.profilePatch(
        before: before,
        desired: {...before, 'name': 'B'},
        current: {...before, 'name': 'C'},
        expected: base,
        actual: latest,
      ),
      throwsA(isA<RecordConflict>()),
    );
    expect(
      RecordConcurrency.profilePatch(
        before: before,
        desired: {...before, 'name': 'B'},
        current: {...before, 'name': 'B'},
        expected: base,
        actual: latest,
      ),
      isEmpty,
    );
    expect(
      () => RecordConcurrency.profilePatch(
        before: before,
        desired: {...before, 'name': 'B'},
        current: before,
        expected: base,
        actual: const RecordVersion(1, 'recreated', 'new'),
      ),
      throwsA(isA<RecordConflict>()),
    );
  });
  test('AppState mengembalikan conflict asli, menjaga draft dan mengakhiri indikator write', () async {
    final repository = MemoryTransactions();
    final state = AppState.forTesting(transactions: repository);
    addTearDown(state.dispose);
    await state.beginSession('A', 'a@example.com');
    final original = TransactionMapper.fromMap('a', data());
    await expectLater(
      state.deleteTransaction('other', previous: original),
      throwsArgumentError,
    );
    repository.emit('A', [original]);
    await Future<void>.delayed(Duration.zero);
    final draft = original.copyWith(description: 'Draft belum hilang');
    repository.writeFailure = const RecordConflict(ConflictReason.changed);
    await expectLater(
      state.updateTransaction('a', draft),
      throwsA(isA<RecordConflict>()),
    );
    expect(state.transactions.single.description, 'Awal');
    expect(draft.description, 'Draft belum hilang');
    expect(state.pendingMutations, 0);
    expect(state.transactionsError, isNull);
  });
  test('AppState profil tidak mengganti snapshot lokal jika field sama berubah di server', () async {
    final profiles = MemoryProfiles();
    final state = AppState.forTesting(profiles: profiles);
    addTearDown(state.dispose);
    await state.beginSession('A', 'a@example.com');
    final base = state.profileSnapshot;
    profiles.profiles['A'] = profiles.profiles['A']!.copyWith(
      name: 'Nama dari B',
    );
    await expectLater(
      state.updateProfile(
        newName: 'Draft A',
        newEmail: state.email,
        newPhone: base.phone,
        newAddress: base.address,
        newCity: base.city,
        newJob: base.job,
        newIncome: base.monthlyIncome,
        previous: base,
      ),
      throwsA(isA<RecordConflict>()),
    );
    expect(state.name, base.name);
    expect(state.profileSaving, isFalse);
    expect(profiles.profiles['A']!.name, 'Nama dari B');
  });
}
