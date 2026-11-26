import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/finance_summary.dart';
import 'package:simanja/core/rupiah.dart';
import 'package:simanja/core/theme.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/screens/analytics_page.dart';
import 'package:simanja/screens/dashboard_page.dart';
import 'package:simanja/screens/data_table_page.dart';

TransactionModel tx(String id, double amount, {bool income = true}) =>
    TransactionModel(
      id: id,
      category: 'Lainnya',
      description: 'Uji',
      amount: amount,
      isIncome: income,
      date: DateTime(2026, 11, 15),
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID', null));
  final max = Rupiah.maxRecord.toDouble();
  final expected = BigInt.parse('9007199254740993');
  test('CSV mempertahankan integer per-record yang sama dengan laporan', () {
    final rows = [tx('1', max), tx('2', 2)];
    final csv = utf8.decode(CsvExporter.encode(rows, 'November 2026'));
    expect(csv, contains('"9007199254740991"'));
    expect(csv, contains('"2"'));
    expect(FinanceSummary.totalIncome(rows), expected);
  });
  test('maxRupiah + 2 tetap tepat pada seluruh agregat dan label', () {
    final rows = [tx('1', max), tx('2', 2)];
    expect(FinanceSummary.totalIncome(rows), expected);
    final series = FinanceSummary.monthlySeries(
      rows,
      monthCount: 2,
      referenceMonth: DateTime(2026, 11),
    );
    expect(series.first.income, BigInt.zero);
    expect(series.last.income, expected);
    expect(series.last.netCashFlow, expected);
    expect(
      NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).rupiah(expected),
      'Rp 9.007.199.254.740.993',
    );
  });
  test(
    'selisih kecil dari agregat besar tidak hilang dan tidak bergantung urutan',
    () {
      final rows = [tx('1', max), tx('2', 2), tx('3', max, income: false)];
      expect(FinanceSummary.netCashFlow(rows), BigInt.two);
      expect(FinanceSummary.netCashFlow(rows.reversed.toList()), BigInt.two);
      expect(
        FinanceSummary.netCashFlow([tx('1', max), tx('2', max, income: false)]),
        BigInt.zero,
      );
      expect(
        FinanceSummary.netCashFlow([
          tx('1', max, income: false),
          tx('2', 2, income: false),
        ]),
        -expected,
      );
    },
  );
  test('total lebih besar dari int64 tidak overflow', () {
    final rows = List.generate(2048, (i) => tx('$i', max, income: false));
    final total = BigInt.from(Rupiah.maxRecord) * BigInt.from(2048);
    expect(FinanceSummary.totalExpense(rows), total);
    expect(FinanceSummary.expenseByCategory(rows)['Lainnya'], total);
    expect(FinanceSummary.netCashFlow(rows), -total);
    expect(Rupiah.digits(total), total.toString());
  });
  test('AppState memakai sumber agregasi tepat yang sama', () async {
    final state = AppState.forTesting();
    await state.addTransaction(tx('1', max));
    await state.addTransaction(tx('2', 2));
    expect(state.totalIncome, expected);
    expect(state.totalExpense, BigInt.zero);
    state.dispose();
  });
  test('batas per-record tetap integer JSON/Firestore dan invalid ditolak', () {
    final map = TransactionMapper.toMap(tx('1', max));
    expect(map['amount'], Rupiah.maxRecord);
    expect(map['amount'], isA<int>());
    expect(
      jsonEncode({'amount': map['amount']}),
      '{"amount":9007199254740991}',
    );
    for (final value in [
      double.nan,
      double.infinity,
      -1.0,
      0.0,
      1.5,
      max + 1,
    ]) {
      expect(
        () => TransactionMapper.toMap(tx('invalid', value)),
        throwsArgumentError,
      );
    }
  });
  test('format signed dan rata-rata tidak melewati floating point', () {
    expect(Rupiah.format(-expected), '-Rp 9.007.199.254.740.993');
    expect(Rupiah.format(BigInt.zero), 'Rp 0');
    expect(Rupiah.average(expected * BigInt.from(6), 6), expected);
    expect(Rupiah.average(BigInt.from(5), 2), BigInt.from(3));
    expect(Rupiah.average(BigInt.from(-5), 2), BigInt.from(-3));
    expect(() => Rupiah.exact(1.5), throwsArgumentError);
    expect(() => Rupiah.average(expected, 0), throwsArgumentError);
  });

  test('notifikasi surplus dan kategori memakai nominal domain tepat', () {
    final income = InAppNotificationItem.buildSummary(
      transactions: [tx('1', max), tx('2', 2)],
    );
    expect(
      income.firstWhere((n) => n.title == 'Surplus Arus Kas').subtitle,
      contains('Rp 9.007.199.254.740.993'),
    );
    final expense = InAppNotificationItem.buildSummary(
      transactions: [tx('1', max, income: false), tx('2', 2, income: false)],
    );
    expect(
      expense
          .firstWhere((n) => n.title.startsWith('Pengeluaran Terbesar'))
          .subtitle,
      contains('Rp 9.007.199.254.740.993'),
    );
  });

  Future<void> seedWidgetState(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..reset();
    for (final row in state.transactions) {
      await state.deleteTransaction(row.id);
    }
    await state.addTransaction(tx('1', max).copyWith(date: DateTime.now()));
    await state.addTransaction(tx('2', 2).copyWith(date: DateTime.now()));
    addTearDown(state.reset);
  }

  testWidgets('ringkasan tabel menampilkan maxRupiah + 2 tanpa pembulatan', (
    tester,
  ) async {
    await seedWidgetState(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const DataTablePage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rp 9.007.199.254.740.993'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tooltip grafik membaca nilai tepat meski koordinat dibulatkan', (
    tester,
  ) async {
    await seedWidgetState(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AnalyticsPage()),
    );
    await tester.pumpAndSettle();
    final bar = tester.widget<BarChart>(find.byType(BarChart));
    final group = bar.data.barGroups.last;
    final barTooltip = bar.data.barTouchData.touchTooltipData.getTooltipItem(
      group,
      bar.data.barGroups.length - 1,
      group.barRods.first,
      0,
    )!;
    expect(
      barTooltip.children!.map((s) => s.toPlainText()).join(),
      contains('Rp 9.007.199.254.740.993'),
    );
    final line = tester.widget<LineChart>(find.byType(LineChart));
    final series = line.data.lineBarsData.first;
    final spot = LineBarSpot(series, 0, series.spots.last);
    final lineTooltip = line.data.lineTouchData.touchTooltipData
        .getTooltipItems([spot])
        .single!;
    expect(
      lineTooltip.children!.map((s) => s.toPlainText()).join(),
      'Rp 9.007.199.254.740.993',
    );
    expect(tester.takeException(), isNull);
  });
}
