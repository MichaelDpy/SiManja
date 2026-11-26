import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/screens/analytics_page.dart';
import 'package:simanja/screens/dashboard_page.dart';
import 'package:simanja/screens/data_table_page.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/screens/login_page.dart';
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

  testWidgets(
    'alur layar login, CRUD, profil, logout dan login ulang dua akun',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState.instance..clearSession();
      final profiles = MemoryProfiles();
      final transactions = MemoryTransactions();
      state.useProfileRepository(profiles);
      state.useTransactionRepository(transactions);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        state.clearSession();
        await auth.events.close();
      });
      Future<void> click(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> tab(String label) => click(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(label),
        ),
      );
      Future<void> login(String email) async {
        await tester.enterText(find.byKey(const Key('login-email')), email);
        await tester.enterText(
          find.byKey(const Key('login-password')),
          'Password-uji123!',
        );
        await click(find.byKey(const Key('login-submit')));
        expect(state.sessionUid, email);
      }

      Future<void> logout() async {
        await tab('Profil');
        await click(find.byKey(const Key('profile-logout')));
        await click(find.byKey(const Key('confirm-logout')));
        expect(find.byType(LoginPage), findsOneWidget);
        expect(state.transactions, isEmpty);
        expect(state.sessionUid, isNull);
        final context = tester.element(find.byType(LoginPage));
        expect(Navigator.of(context).canPop(), isFalse);
      }

      Finder input(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.pumpWidget(SimanjaApp(initialRoute: '/login', auth: auth));
      await tester.pumpAndSettle();
      await login('a@example.com');
      expect(state.transactions, isEmpty);
      await tab('Transaksi');
      await click(find.byTooltip('Tambah Transaksi'));
      await click(find.byType(DropdownButton<CategoryMeta>));
      await click(find.text('Gaji').last);
      await tester.enterText(input('Keterangan'), 'Gaji uji presentasi');
      await tester.enterText(input('Jumlah (Rp)'), '100000');
      await click(find.widgetWithText(ElevatedButton, 'Tambah Transaksi'));
      expect(state.transactions.single.description, 'Gaji uji presentasi');
      final id = state.transactions.single.id;
      expect(transactions.rows['a@example.com']!.single.id, id);
      expect(find.text('Transaksi ditambahkan'), findsOneWidget);
      await tab('Data');
      expect(find.text('Gaji uji presentasi'), findsOneWidget);
      await tab('Analitik');
      expect(
        tester
            .widget<BarChart>(find.byType(BarChart))
            .data
            .barGroups
            .last
            .barRods
            .first
            .toY,
        100000,
      );
      await tab('Transaksi');
      await click(find.byIcon(Icons.edit_outlined));
      await tester.enterText(input('Jumlah (Rp)'), '150000');
      await click(find.widgetWithText(ElevatedButton, 'Simpan Perubahan'));
      expect(state.transactions.single.id, id);
      expect(state.totalIncome, BigInt.from(150000));
      await tab('Profil');
      final name = find.byKey(const Key('profile-name'));
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Nama akun presentasi');
      await click(find.byKey(const Key('profile-save')));
      expect(profiles.profiles['a@example.com']!.name, 'Nama akun presentasi');
      await logout();
      expect(transactions.subscriptions['a@example.com'], 0);
      await login('b@example.com');
      expect(state.transactions, isEmpty);
      expect(state.name, 'b');
      await logout();
      await login('a@example.com');
      expect(state.name, 'Nama akun presentasi');
      expect(state.transactions.single.id, id);
      expect(state.totalIncome, BigInt.from(150000));
      await tab('Transaksi');
      // Spinner hapus tetap aktif selama dialog konfirmasi terbuka.
      await tester.tap(find.byIcon(Icons.delete_outline).hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(TextButton, 'Hapus'));
      await tester.pumpAndSettle();
      expect(state.transactions, isEmpty);
      expect(transactions.rows['a@example.com'], isEmpty);
      await tab('Analitik');
      expect(find.byType(BarChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
