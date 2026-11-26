import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/repositories/transaction_repository.dart';

void main() {
  final fixture = jsonDecode(
    File('../backend/test/fixtures/date-migration.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Timestamp stamp(Map<String, dynamic> value) =>
      Timestamp(value['seconds'] as int, value['nanoseconds'] as int);
  final original = <String, dynamic>{
    'category': 'Gaji',
    'description': 'Fixture migrasi',
    'amount': 9007199254740991,
    'isIncome': true,
    'date': stamp(fixture['legacyDate'] as Map<String, dynamic>),
    'createdAt': Timestamp(1769900000, 0),
    'updatedAt': Timestamp(1769990000, 0),
  };

  test('payload migrasi backend dapat dibaca sebagai kalender v2 tanpa kehilangan rupiah', () {
    final migrated = {
      ...original,
      'dateVersion': 2,
      'date': stamp(fixture['migratedDate'] as Map<String, dynamic>),
    };
    final model = TransactionMapper.fromMap('fixture', migrated);
    expect(model.date, DateTime.utc(2026, 1, 31));
    expect(model.date.isUtc, isTrue);
    expect(model.needsDateReview, isFalse);
    expect(model.amount.toInt(), 9007199254740991);
    final encoded = TransactionMapper.toMap(model);
    expect(encoded['date'], migrated['date']);
    expect(encoded['dateVersion'], 2);
    expect(encoded['amount'], original['amount']);
  });

  test('record yang dilewati migrasi tetap legacy dan edit non-tanggal mempertahankan instant', () {
    final model = TransactionMapper.fromMap('fixture', original);
    expect(model.needsDateReview, isTrue);
    final encoded = TransactionMapper.toMap(
      model.copyWith(description: 'Edit'),
    );
    expect(encoded['date'], original['date']);
    expect(encoded.containsKey('dateVersion'), isFalse);
  });
}
