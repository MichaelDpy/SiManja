import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/finance_summary.dart';
import 'package:simanja/core/rupiah.dart';
import 'package:simanja/core/theme.dart';
import 'package:simanja/screens/data_table_page.dart';
import 'package:simanja/screens/analytics_page.dart';

import 'support/memory_history.dart';
import 'support/memory_profiles.dart';

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });
  Future<MemoryHistory> mount(WidgetTester tester, {double width = 412}) async {
    tester.view.physicalSize = Size(width, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..clearSession();
    final repository = MemoryHistory()..rows['A'] = reportFixture();
    state.useProfileRepository(MemoryProfiles());
    state.useTransactionRepository(repository);
    await state.beginSession('A', 'a@example.test');
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const DataTablePage()),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
    });
    return repository;
  }

  testWidgets(
    'paging on 320px preserves full summary and search on hidden pages',
    (tester) async {
      await mount(tester, width: 320);
      expect(find.text('1–50 dari 137 transaksi'), findsOneWidget);
      expect(find.text('137 transaksi'), findsOneWidget);
      expect(find.text('needle 0'), findsNothing);
      expect(
        find.text(Rupiah.format(FinanceSummary.totalIncome(reportFixture()))),
        findsWidgets,
      );
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('51–100 dari 137 transaksi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('101–137 dari 137 transaksi'), findsOneWidget);
      expect(find.text('needle 0'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'needle');
      await tester.pumpAndSettle();
      expect(find.text('2 transaksi'), findsOneWidget);
      expect(
        find.text(
          Rupiah.format(BigInt.from(9007199254740991) + BigInt.from(236)),
        ),
        findsWidgets,
      );
      expect(find.byKey(const Key('report-page-range')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial cache disables export; server/realtime/reload restores full selection',
    (tester) async {
      final repository = await mount(tester);
      repository.emit('A', reportFixture(3), cache: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('report-completeness')), findsOneWidget);
      IconButton exportButton() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.download_outlined),
      );
      expect(exportButton().onPressed, isNull);
      repository.emit('A', reportFixture());
      await tester.pumpAndSettle();
      expect(exportButton().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      repository.emit('A', reportFixture(138));
      await tester.pumpAndSettle();
      expect(find.text('1–50 dari 138 transaksi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-reload')));
      await tester.pumpAndSettle();
      expect(find.text('138 transaksi'), findsOneWidget);
      expect(find.byKey(const Key('report-completeness')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('analytics receives every row after paging the table', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const Key('report-next')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AnalyticsPage()),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(
      chart.data.barGroups.last.barRods.first.toY,
      FinanceSummary.totalIncome(reportFixture()).toDouble(),
    );
    expect(AppState.instance.transactions, hasLength(137));
    expect(tester.takeException(), isNull);
  });
}
