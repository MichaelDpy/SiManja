import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

TransactionModel transaction({String id = 'stable', double amount = 123456}) =>
    TransactionModel(
      id: id,
      category: 'Kategori baru',
      description: 'Transaksi tes',
      amount: amount,
      isIncome: false,
      date: DateTime(2026, 11, 19),
    );

Map<String, dynamic> document() => {
  ...TransactionMapper.toMap(transaction()),
  'createdAt': Timestamp.fromDate(DateTime(2026, 11, 19)),
  'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 19)),
};

void main() {
  test(
    'round trip mempertahankan ID, rupiah integer, dan tanggal kalender lokal',
    () {
      final tx = transaction();
      final payload = TransactionMapper.toMap(tx);
      expect(payload['amount'], isA<int>());
      expect(payload.keys.toSet(), {
        'category',
        'description',
        'amount',
        'isIncome',
        'date',
      });
      final restored = TransactionMapper.fromMap(tx.id, document());
      expect(restored.id, tx.id);
      expect(restored.amount, tx.amount);
      expect(restored.date, tx.date);
      expect(restored.category, 'Kategori baru');
      expect(CategoryMeta.of(restored.category).icon, isNotNull);
    },
  );
  test('jam tidak menggeser tanggal yang dipilih', () {
    final tx = transaction().copyWith(date: DateTime(2026, 12, 31, 23, 59));
    final date = (TransactionMapper.toMap(tx)['date'] as Timestamp).toDate();
    expect(date, DateTime(2026, 12, 31));
  });
  for (final amount in [
    0.0,
    -1.0,
    1.5,
    double.nan,
    double.infinity,
    9007199254740992.0,
  ]) {
    test('nominal tidak valid ditolak: $amount', () {
      expect(
        () => TransactionMapper.toMap(transaction(amount: amount)),
        throwsArgumentError,
      );
    });
  }
  test('kategori, deskripsi dan tanggal tidak valid ditolak', () {
    for (final tx in [
      transaction().copyWith(category: ' '),
      transaction().copyWith(category: 'x' * 121),
      transaction().copyWith(description: ''),
      transaction().copyWith(description: 'x' * 1001),
      transaction().copyWith(date: DateTime(1800)),
      transaction().copyWith(date: DateTime(2201)),
    ]) {
      expect(() => TransactionMapper.toMap(tx), throwsArgumentError);
    }
  });
  test('tipe dokumen salah tidak dikonversi menjadi nilai palsu', () {
    for (final bad in [
      <String, dynamic>{},
      {...document(), 'amount': '100'},
      {...document(), 'amount': 1.5},
      {...document(), 'isIncome': 'true'},
      {...document(), 'date': '2026-11-19'},
      {...document(), 'updatedAt': 'invalid'},
    ]) {
      expect(
        () => TransactionMapper.fromMap('stable', bad),
        throwsFormatException,
      );
    }
  });
  test('timestamp null hanya diizinkan pada snapshot dengan pending write', () {
    final pending = {...document(), 'createdAt': null, 'updatedAt': null};
    expect(
      () => TransactionMapper.fromMap('stable', pending),
      throwsFormatException,
    );
    expect(
      TransactionMapper.fromMap(
        'stable',
        pending,
        allowPendingTimestamps: true,
      ).amount,
      123456,
    );
    pending.remove('createdAt');
    expect(
      () => TransactionMapper.fromMap(
        'stable',
        pending,
        allowPendingTimestamps: true,
      ),
      throwsFormatException,
    );
  });
  test('snapshot tidak mengekspos list yang dapat diubah oleh widget', () {
    final source = [transaction()];
    final snapshot = TransactionSnapshot(
      source,
      fromCache: true,
      hasPendingWrites: true,
    );
    source.clear();
    expect(snapshot.transactions, hasLength(1));
    expect(() => snapshot.transactions.clear(), throwsUnsupportedError);
    expect(snapshot.fromCache, isTrue);
    expect(snapshot.hasPendingWrites, isTrue);
  });
  test('path UID/ID dan penggantian ID ditolak sebelum akses SDK', () async {
    final repository = FirestoreTransactionRepository.lazy(
      () => throw StateError('SDK tidak boleh dipanggil'),
    );
    for (final id in ['', ' ', '.', '..', 'other/path', 'x' * 1501]) {
      expect(() => TransactionMapper.validateId(id), throwsArgumentError);
      expect(() => repository.newId(id), throwsArgumentError);
      expect(() => repository.watch(id), throwsArgumentError);
      await expectLater(repository.add(id, transaction()), throwsArgumentError);
      expect(() => repository.delete('A', id), throwsArgumentError);
    }
    await expectLater(
      repository.update('A', 'different', transaction()),
      throwsArgumentError,
    );
  });
}
