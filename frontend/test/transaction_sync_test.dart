import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/screens/analytics_page.dart';
import 'package:simanja/screens/dashboard_page.dart';
import 'package:simanja/screens/data_table_page.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/services/auth_service.dart';
import 'package:simanja/widgets/transaction_sync_status.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

TransactionModel syncedTransaction(double amount) => TransactionModel(
  id: 'remote',
  category: 'Gaji',
  description: 'Transaksi sinkron',
  amount: amount,
  isIncome: true,
  date: DateTime.now(),
);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  testWidgets('snapshot memperbarui dasbor, transaksi, tabel dan grafik', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..clearSession();
    final repository = MemoryTransactions();
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
      await auth.events.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGate(
          auth: auth,
          profiles: MemoryProfiles(),
          transactions: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.emit('A', [syncedTransaction(12000)]);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Transaksi sinkron'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(DashboardPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(
        of: find.byType(DashboardPage),
        matching: find.text('Transaksi sinkron'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi sinkron'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.table_chart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi sinkron'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.bar_chart_outlined),
      ),
    );
    await tester.pumpAndSettle();
    BarChart analyticsChart() => tester.widget<BarChart>(
      find.descendant(
        of: find.byType(AnalyticsPage),
        matching: find.byType(BarChart),
      ),
    );
    double lastIncome() =>
        analyticsChart().data.barGroups.last.barRods.first.toY;
    expect(lastIncome(), 12000);
    repository.emit('A', [syncedTransaction(24000)]);
    await tester.pumpAndSettle();
    expect(lastIncome(), 24000);
    repository.emit('A', []);
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsNothing);
    await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi sinkron'), findsNothing);
    expect(repository.subscriptions['A'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('indikator membedakan cache, write tertunda dan error retry', (
    tester,
  ) async {
    final repository = MemoryTransactions();
    final state = AppState.forTesting(transactions: repository);
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
    repository.emit('A', [], cache: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Data cache/offline'), findsOneWidget);
    repository.pendingWrite = Completer<void>();
    final request = state.addTransaction(syncedTransaction(12000));
    await tester.pump();
    expect(find.textContaining('menunggu konfirmasi server'), findsOneWidget);
    repository.writeFailure = StateError('denied');
    final rejected = expectLater(request, throwsStateError);
    repository.pendingWrite!.complete();
    await rejected;
    await tester.pumpAndSettle();
    expect(find.textContaining('menunggu konfirmasi server'), findsNothing);
    expect(state.transactions, isEmpty);
    repository.events['A']!.addError(StateError('stream failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Transaksi belum dapat dimuat'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Transaksi belum dapat dimuat'), findsNothing);
    expect(repository.subscriptions['A'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabel dengan data tetap dapat digeser di layar 320', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..clearSession();
    final repository = MemoryTransactions();
    state.useTransactionRepository(repository);
    state.useProfileRepository(MemoryProfiles());
    await state.beginSession('A', 'a@example.com');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
    });
    await tester.pumpWidget(const MaterialApp(home: DataTablePage()));
    repository.emit('A', [syncedTransaction(12000)]);
    await tester.pumpAndSettle();
    expect(find.text('Transaksi sinkron'), findsOneWidget);
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsOneWidget);
    await tester.drag(horizontal, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
