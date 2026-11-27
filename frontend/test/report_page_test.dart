import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/finance_summary.dart';
import 'package:simanja/core/rupiah.dart';
import 'package:simanja/core/theme.dart';
import 'package:simanja/models/transaction_model.dart';
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
      expect(find.text('1â€“50 dari 137 transaksi'), findsOneWidget);
      expect(find.text('137 transaksi'), findsOneWidget);
      expect(find.text('needle 0'), findsNothing);
      expect(
        find.text(Rupiah.format(FinanceSummary.totalIncome(reportFixture()))),
        findsWidgets,
      );
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('51â€“100 dari 137 transaksi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-next')));
      await tester.pumpAndSettle();
      expect(find.text('101â€“137 dari 137 transaksi'), findsOneWidget);
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
      expect(find.text('1â€“50 dari 138 transaksi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-reload')));
      await tester.pumpAndSettle();
      expect(find.text('138 transaksi'), findsOneWidget);
      expect(find.byKey(const Key('report-completeness')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search retains focus while characters arrive across rebuilds', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.testTextInput.enterText('p');
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    tester.testTextInput.enterText('pr');
    await tester.pump();
    tester.testTextInput.enterText('needle');
    await tester.pumpAndSettle();
    expect(find.text('2 transaksi'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

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

  // â”€â”€ A1-05: regresi filter bulan dipertahankan saat record terakhir hilang â”€

  /// Fixture multi-bulan: 3 transaksi Oktober, 1 transaksi November.
  List<TransactionModel> multiMonthFixture() => [
    TransactionModel(
      id: 'oct-1',
      category: 'Gaji',
      description: 'Pemasukan Oktober',
      amount: 5000,
      isIncome: true,
      date: DateTime.utc(2026, 10, 1),
    ),
    TransactionModel(
      id: 'oct-2',
      category: 'Belanja',
      description: 'Belanja Oktober',
      amount: 2000,
      isIncome: false,
      date: DateTime.utc(2026, 10, 15),
    ),
    TransactionModel(
      id: 'oct-3',
      category: 'Gaji',
      description: 'Bonus Oktober',
      amount: 1000,
      isIncome: true,
      date: DateTime.utc(2026, 10, 31),
    ),
    TransactionModel(
      id: 'nov-1',
      category: 'Gaji',
      description: 'Pemasukan November',
      amount: 7000,
      isIncome: true,
      date: DateTime.utc(2026, 11, 1),
    ),
  ];

  Future<MemoryHistory> mountMultiMonth(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..clearSession();
    final repository = MemoryHistory()..rows['A'] = multiMonthFixture();
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
    'A1-05: pilih Oktober lalu hapus semua record Oktober â†’ pilihan tetap Oktober, empty state tampil',
    (tester) async {
      final repository = await mountMultiMonth(tester);

      // Pilih filter Oktober 2026 â€” tap pada label "Semua" yang tampil di dropdown
      await tester.tap(find.text('Semua').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okt 2026').last);
      await tester.pumpAndSettle();

      // Verifikasi 3 transaksi Oktober tampil
      expect(find.text('3 transaksi'), findsOneWidget);

      // Emit snapshot tanpa transaksi Oktober â€” hanya November tersisa
      repository.emit('A', [multiMonthFixture().last]);
      await tester.pumpAndSettle();

      // Kriteria A1-05: filter TIDAK di-reset ke "Semua" diam-diam
      // â†’ tampilkan empty state, bukan 1 transaksi November
      expect(
        find.text('1 transaksi'),
        findsNothing,
        reason:
            'Filter Oktober tidak boleh direset ke Semua saat record hilang',
      );
      expect(
        find.text('Tidak Ada Hasil'),
        findsOneWidget,
        reason: 'Empty state harus tampil saat bulan terpilih kosong',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A1-05: reset manual filter setelah bulan kosong â†’ kembali tampilkan semua',
    (tester) async {
      final repository = await mountMultiMonth(tester);

      // Pilih Oktober, lalu hapus semua record Oktober
      await tester.tap(find.text('Semua').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okt 2026').last);
      await tester.pumpAndSettle();
      repository.emit('A', [multiMonthFixture().last]);
      await tester.pumpAndSettle();

      // Empty state harus punya tombol Reset Filter
      final resetButton = find.widgetWithText(TextButton, 'Reset Filter');
      expect(resetButton, findsOneWidget);
      await tester.tap(resetButton);
      await tester.pumpAndSettle();

      // Setelah reset manual, harus tampil 1 transaksi November
      expect(find.text('1 transaksi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A1-05: loading/error/data-kembali tidak mereset filter diam-diam',
    (tester) async {
      final repository = await mountMultiMonth(tester);

      // Pilih Oktober
      await tester.tap(find.text('Semua').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okt 2026').last);
      await tester.pumpAndSettle();
      expect(find.text('3 transaksi'), findsOneWidget);

      // Emit snapshot cache (data sementara berkurang) â€” filter tetap Oktober
      repository.emit('A', multiMonthFixture(), cache: true);
      await tester.pumpAndSettle();
      expect(
        find.text('3 transaksi'),
        findsOneWidget,
        reason: 'Filter Oktober harus bertahan saat cache update',
      );

      // Emit data penuh kembali â€” filter masih Oktober
      repository.emit('A', multiMonthFixture());
      await tester.pumpAndSettle();
      expect(
        find.text('3 transaksi'),
        findsOneWidget,
        reason: 'Filter Oktober harus bertahan saat data penuh kembali',
      );
      expect(tester.takeException(), isNull);
    },
  );

  // ── A1-06: regresi navigasi analitik mencakup masa depan ─────────────

  Future<void> mountAnalytics(
    WidgetTester tester,
    List<TransactionModel> rows,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState.instance..clearSession();
    final repository = MemoryHistory()..rows['A'] = rows;
    state.useProfileRepository(MemoryProfiles());
    state.useTransactionRepository(repository);
    await state.beginSession('A', 'a@example.test');
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AnalyticsPage()),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
    });
  }

  // Helper: cari IconButton dengan tooltip tertentu
  IconButton _iconBtnByTooltip(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip),
      );

  testWidgets(
    'A1-06: transaksi masa depan dapat dituju via navigasi maju analitik',
    (tester) async {
      final now = DateTime.now();
      final futureMonth = DateTime(now.year + 1, 1);
      final futureTx = TransactionModel(
        id: 'future-1',
        category: 'Gaji',
        description: 'Pemasukan masa depan',
        amount: 9000,
        isIncome: true,
        date: DateTime.utc(futureMonth.year, futureMonth.month, 15),
      );
      await mountAnalytics(tester, [futureTx]);

      // Tombol maju harus aktif dari anchor bulan sekarang
      expect(
        _iconBtnByTooltip(tester, 'Periode berikutnya').onPressed,
        isNotNull,
        reason: 'Tombol maju harus aktif dari anchor bulan sekarang',
      );

      // Navigasi maju sampai mencapai bulan transaksi masa depan
      final stepsNeeded =
          (futureMonth.year - now.year) * 12 + (futureMonth.month - now.month);
      for (var i = 0; i < stepsNeeded; i++) {
        await tester.tap(find.byTooltip('Periode berikutnya'));
        await tester.pumpAndSettle();
      }

      // Label rentang harus mencakup tahun masa depan
      expect(
        find.textContaining('${futureMonth.year}'),
        findsWidgets,
        reason: 'Label periode harus menampilkan tahun masa depan',
      );

      // Bar chart bulan terakhir harus punya nilai > 0
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(
        chart.data.barGroups.last.barRods.first.toY,
        greaterThan(0),
        reason: 'Transaksi masa depan harus muncul di grafik analitik',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A1-06: tombol maju dinonaktifkan persis di batas Des tahun+1', (
    tester,
  ) async {
    final now = DateTime.now();
    await mountAnalytics(tester, []);

    final target = DateTime(now.year + 1, 12);
    final stepsToTarget =
        (target.year - now.year) * 12 + (target.month - now.month);
    for (var i = 0; i < stepsToTarget; i++) {
      expect(
        _iconBtnByTooltip(tester, 'Periode berikutnya').onPressed,
        isNotNull,
        reason: 'Tombol maju harus aktif sebelum mencapai batas',
      );
      await tester.tap(find.byTooltip('Periode berikutnya'));
      await tester.pumpAndSettle();
    }

    // Di batas Des tahun+1, tombol maju harus dinonaktifkan
    expect(
      _iconBtnByTooltip(tester, 'Periode berikutnya').onPressed,
      isNull,
      reason: 'Tombol maju harus dinonaktifkan di batas Des tahun+1',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('A1-06: expense-only dan bulan nol tidak crash navigasi maju', (
    tester,
  ) async {
    final now = DateTime.now();
    final expenseTx = TransactionModel(
      id: 'exp-1',
      category: 'Belanja',
      description: 'Pengeluaran saja',
      amount: 3000,
      isIncome: false,
      date: DateTime.utc(now.year + 1, 6, 1),
    );
    await mountAnalytics(tester, [expenseTx]);

    // Navigasi maju beberapa bulan tanpa crash meski ada bulan nol
    for (var i = 0; i < 3; i++) {
      final btn = _iconBtnByTooltip(tester, 'Periode berikutnya');
      if (btn.onPressed == null) break;
      await tester.tap(find.byTooltip('Periode berikutnya'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
