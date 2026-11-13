import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:simanja/core/theme.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/screens/dashboard_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  TransactionModel makeTx({
    required String id,
    required String category,
    required String description,
    required double amount,
    required bool isIncome,
    required DateTime date,
  }) {
    return TransactionModel(
      id: id,
      category: category,
      description: description,
      amount: amount,
      isIncome: isIncome,
      date: date,
    );
  }

  group('InAppNotificationItem.buildSummary', () {
    test('mengembalikan list kosong jika tidak ada transaksi', () {
      final notifs = InAppNotificationItem.buildSummary(transactions: []);
      expect(notifs, isEmpty);
    });

    test('meringkas transaksi terakhir pemasukan dengan benar', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Gaji',
          description: 'Gaji Bulanan',
          amount: 10000000,
          isIncome: true,
          date: DateTime(2026, 11, 10),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      expect(notifs.isNotEmpty, isTrue);
      final latest = notifs.first;
      expect(latest.title, 'Pemasukan Terakhir');
      expect(latest.subtitle, contains('Gaji Bulanan'));
      expect(latest.subtitle, contains('Gaji'));
      expect(latest.subtitle, contains('10.000.000'));
      expect(latest.color, AppColors.income);
      expect(latest.icon, Icons.arrow_downward);
    });

    test('meringkas transaksi terakhir pengeluaran dengan benar', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Makanan',
          description: 'Makan Siang',
          amount: 50000,
          isIncome: false,
          date: DateTime(2026, 11, 12),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final latest = notifs.first;
      expect(latest.title, 'Pengeluaran Terakhir');
      expect(latest.subtitle, contains('Makan Siang'));
      expect(latest.subtitle, contains('50.000'));
      expect(latest.color, AppColors.expense);
      expect(latest.icon, Icons.arrow_upward);
    });

    test('mendeteksi kondisi defisit arus kas saat pengeluaran > pemasukan', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Elektronik',
          description: 'Beli Monitor',
          amount: 3000000,
          isIncome: false,
          date: DateTime(2026, 11, 5),
        ),
        makeTx(
          id: 'tx-2',
          category: 'Freelance',
          description: 'Proyek Sampingan',
          amount: 1000000,
          isIncome: true,
          date: DateTime(2026, 11, 1),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final deficitNotif = notifs.firstWhere(
        (n) => n.title == 'Defisit Arus Kas',
      );
      expect(deficitNotif.icon, Icons.warning_amber_rounded);
      expect(deficitNotif.color, AppColors.expense);
      expect(deficitNotif.subtitle, contains('3.000.000'));
      expect(deficitNotif.subtitle, contains('1.000.000'));
      expect(deficitNotif.time, 'Nov 2026');
    });

    test('mendeteksi surplus arus kas saat pemasukan > pengeluaran', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Gaji',
          description: 'Gaji Pokok',
          amount: 8000000,
          isIncome: true,
          date: DateTime(2026, 11, 1),
        ),
        makeTx(
          id: 'tx-2',
          category: 'Belanja',
          description: 'Belanja Bulanan',
          amount: 2000000,
          isIncome: false,
          date: DateTime(2026, 11, 2),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final surplusNotif = notifs.firstWhere(
        (n) => n.title == 'Surplus Arus Kas',
      );
      expect(surplusNotif.icon, Icons.trending_up);
      expect(surplusNotif.color, AppColors.income);
      expect(surplusNotif.subtitle, contains('+Rp 6.000.000'));
      expect(surplusNotif.time, 'Nov 2026');
    });

    test('mendeteksi arus kas seimbang saat pemasukan == pengeluaran', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Gaji',
          description: 'Bonus',
          amount: 500000,
          isIncome: true,
          date: DateTime(2026, 11, 1),
        ),
        makeTx(
          id: 'tx-2',
          category: 'Makanan',
          description: 'Makan',
          amount: 500000,
          isIncome: false,
          date: DateTime(2026, 11, 2),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final balanceNotif = notifs.firstWhere(
        (n) => n.title == 'Arus Kas Seimbang',
      );
      expect(balanceNotif.icon, Icons.balance);
      expect(balanceNotif.color, AppColors.teal);
    });

    test('menampilkan kategori pengeluaran terbesar', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Makanan',
          description: 'Restoran',
          amount: 300000,
          isIncome: false,
          date: DateTime(2026, 11, 3),
        ),
        makeTx(
          id: 'tx-2',
          category: 'Transport',
          description: 'Bensin & Tol',
          amount: 750000,
          isIncome: false,
          date: DateTime(2026, 11, 4),
        ),
      ];

      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final topExpense = notifs.firstWhere(
        (n) => n.title.startsWith('Pengeluaran Terbesar'),
      );
      expect(topExpense.title, contains('Transport'));
      expect(topExpense.subtitle, contains('750.000'));
    });

    test('mengevaluasi rasio tabungan yang sehat (>= 20%)', () {
      final txList = [
        makeTx(
          id: 'tx-1',
          category: 'Gaji',
          description: 'Gaji',
          amount: 10000000,
          isIncome: true,
          date: DateTime(2026, 11, 1),
        ),
        makeTx(
          id: 'tx-2',
          category: 'Belanja',
          description: 'Belanja',
          amount: 6000000,
          isIncome: false,
          date: DateTime(2026, 11, 2),
        ),
      ];

      // Rasio tabungan = (10jt - 6jt) / 10jt = 40%
      final notifs = InAppNotificationItem.buildSummary(
        transactions: txList,
        periodLabel: 'Nov 2026',
      );

      final savingsNotif = notifs.firstWhere(
        (n) => n.title.contains('Rasio Tabungan Baik'),
      );
      expect(savingsNotif.title, contains('40.0%'));
      expect(savingsNotif.color, AppColors.income);
    });
  });
}
