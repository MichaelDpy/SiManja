import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/calendar_date.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/finance_summary.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

TransactionModel row(DateTime date) => TransactionModel(
  id: 'date-test',
  category: 'Gaji',
  description: 'Uji tanggal',
  amount: 10,
  isIncome: true,
  date: date,
);

Map<String, dynamic> stored(Timestamp date, {Object? version = 2}) => {
  'category': 'Gaji',
  'description': 'Uji tanggal',
  'amount': 10,
  'isIncome': true,
  'date': date,
  'dateVersion': ?version,
  'createdAt': Timestamp(1234567890, 123456789),
  'updatedAt': Timestamp(1234567900, 987654321),
};

void main() {
  final expectedOffset = Platform.environment['SIMANJA_TEST_TZ_OFFSET'];
  if (expectedOffset != null) {
    test('zona proses native benar-benar memakai offset yang diminta', () {
      expect(
        DateTime(2026, 1, 1).timeZoneOffset.inMinutes,
        int.parse(expectedOffset),
      );
    });
  }
  final dates = [
    DateTime.utc(1900, 1, 1),
    DateTime.utc(2024, 2, 29),
    DateTime.utc(2025, 12, 31),
    DateTime.utc(2026, 1, 1),
    DateTime.utc(2026, 11, 30),
    DateTime.utc(2026, 12, 1),
    DateTime.utc(2199, 1, 1),
    DateTime.utc(2200, 12, 31),
  ];

  for (final day in dates) {
    test('round trip kalender UTC dan lokal: ${day.toIso8601String()}', () {
      for (final selected in [
        day,
        DateTime(day.year, day.month, day.day, 23, 59),
      ]) {
        final payload = TransactionMapper.toMap(row(selected));
        expect(payload['dateVersion'], 2);
        expect(payload['date'], Timestamp.fromDate(day));
        final decoded = TransactionMapper.fromMap('date-test', {
          ...stored(payload['date'] as Timestamp),
          ...payload,
        });
        expect(decoded.date, day);
        expect(decoded.needsDateReview, isFalse);
        expect(TransactionMapper.toMap(decoded), payload);
      }
    });
  }

  // Fixed-offset fixtures model travel without changing the host OS timezone.
  // They also demonstrate why a legacy timestamp cannot identify its source day.
  for (final zone in <String, int>{
    'Asia/Jakarta': 7,
    'Asia/Bangkok': 7,
    'UTC': 0,
    'America/Los_Angeles winter': -8,
    'Pacific/Kiritimati': 14,
  }.entries) {
    test('calendar date tidak mengikuti proyeksi instant ${zone.key}', () {
      final canonical = DateTime.utc(2026, 1, 1);
      final localClock = canonical.add(Duration(hours: zone.value));
      final decoded = TransactionMapper.fromMap(
        'date-test',
        stored(Timestamp.fromDate(canonical)),
      );
      expect(decoded.date, canonical);
      expect(decoded.date.day, 1);
      if (zone.value < 0) expect(localClock.day, 31);
      expect(
        utf8.decode(CsvExporter.encode([decoded], 'Tanggal')),
        contains('"2026-01-01"'),
      );
    });
  }

  test('filter kalender memakai komponen hari untuk facade UTC/lokal', () {
    final rows = [
      row(DateTime.utc(2025, 12, 31, 23, 59)),
      row(DateTime.utc(2026, 1, 1)),
      row(DateTime(2026, 1, 31, 23, 59)),
      row(DateTime.utc(2026, 2, 1)),
    ];
    final january = FinanceSummary.filterMonth(rows, year: 2026, month: 1);
    expect(january, hasLength(2));
    expect(january.map((t) => t.date.day), [1, 31]);
    expect(FinanceSummary.totalIncome(january), BigInt.from(20));
    expect(
      FinanceSummary.filterPeriod(
        rows,
        from: DateTime.utc(2026, 1, 1),
        until: DateTime(2026, 2, 1),
      ),
      january,
    );
  });

  test(
    'legacy tetap ambigu dan edit non-tanggal tidak memigrasikan timestamp',
    () {
      final instant = Timestamp.fromDate(
        DateTime.parse('2026-01-31T00:00:00+07:00'),
      );
      final legacy = TransactionMapper.fromMap(
        'date-test',
        stored(instant, version: null),
      );
      expect(legacy.needsDateReview, isTrue);
      expect(legacy.date, instant.toDate().toLocal());
      final changed = legacy.copyWith(
        description: 'Keterangan baru',
        date: CalendarDate.canonical(legacy.date),
      );
      final payload = TransactionMapper.toMap(changed);
      expect(payload['date'], instant);
      expect(payload.containsKey('dateVersion'), isFalse);
      final nextDay = legacy.copyWith(date: DateTime.utc(2026, 2, 2));
      expect(nextDay.needsDateReview, isFalse);
      expect(TransactionMapper.toMap(nextDay)['dateVersion'], 2);
    },
  );

  test('legacy mempertahankan nanodetik saat hanya keterangan diubah', () {
    final instant = Timestamp(1769792400, 123456789);
    final legacy = TransactionMapper.fromMap(
      'date-test',
      stored(instant, version: null),
    );
    expect(
      TransactionMapper.toMap(legacy.copyWith(description: 'Baru'))['date'],
      instant,
    );
  });

  test('unknown version dan tanggal v2 non-midnight tidak ditafsirkan sebagai legacy', () {
    final midnight = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
    for (final version in [0, 1, 3, '2', 2.0, true]) {
      expect(
        () => TransactionMapper.fromMap(
          'date-test',
          stored(midnight, version: version),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => TransactionMapper.fromMap('date-test', {
        ...stored(midnight),
        'dateVersion': null,
      }),
      throwsFormatException,
    );
    for (final instant in [
      Timestamp(midnight.seconds, 1),
      Timestamp(midnight.seconds + 1, 0),
    ]) {
      expect(
        () => TransactionMapper.fromMap('date-test', stored(instant)),
        throwsFormatException,
      );
    }
  });

  test('pending metadata diizinkan terpisah dari tanggal kalender', () {
    final data = {
      ...stored(Timestamp.fromDate(DateTime.utc(2026, 1, 1))),
      'createdAt': null,
      'updatedAt': null,
    };
    expect(
      TransactionMapper.fromMap(
        'date-test',
        data,
        allowPendingTimestamps: true,
      ).date,
      DateTime.utc(2026, 1, 1),
    );
    expect(
      () => TransactionMapper.fromMap('date-test', data),
      throwsFormatException,
    );
    expect(
      () => TransactionMapper.fromMap('date-test', {
        ...data,
        'date': null,
      }, allowPendingTimestamps: true),
      throwsFormatException,
    );
    expect(data['createdAt'], isNull);
  });
}
