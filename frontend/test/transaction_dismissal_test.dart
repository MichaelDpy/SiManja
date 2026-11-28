import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// A1-09 — Lengkapi dirty state dan dismissal transaksi.
///
/// Memverifikasi dismissal modal AKTUAL (Back, close, tap luar barrier,
/// swipe-down sheet) di atas state clean/dirty/pending, plus jaminan
/// pending/lost-ack/retry/UID-switch tanpa write ganda / feedback sesi lama.
void main() {
  final state = AppState.instance;
  late MemoryTransactions repository;
  late SessionAuth auth;

  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  setUp(() {
    state.clearSession();
    repository = MemoryTransactions();
    state.useTransactionRepository(repository);
    state.useProfileRepository(MemoryProfiles());
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
  });

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  bool sheetOpen() => find.text('Tambah Transaksi').evaluate().isNotEmpty;
  bool discardDialogOpen() =>
      find.text('Buang perubahan?').evaluate().isNotEmpty;

  Future<void> openAddForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
      await auth.events.close();
    });
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Transaksi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tambah Transaksi'));
    await tester.pumpAndSettle();
  }

  Future<void> pickCategory(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButton<CategoryMeta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> pickDate(WidgetTester tester, DateTime date) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final calendar = find.byIcon(Icons.calendar_today_outlined);
    await tester.ensureVisible(calendar);
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(DatePickerDialog));
    final labels = MaterialLocalizations.of(ctx);
    await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    final dateInput = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dateInput, labels.formatCompactDate(date));
    await tester.tap(find.text(labels.okButtonLabel));
    await tester.pumpAndSettle();
  }

  // ── Dismissal: clean ─────────────────────────────────────────────────────

  group('clean state', () {
    testWidgets('form baru bersih: Back menutup tanpa konfirmasi', (
      tester,
    ) async {
      await openAddForm(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(discardDialogOpen(), isFalse);
      expect(repository.writes, 0);
    });

    testWidgets('form baru bersih: close menutup tanpa konfirmasi', (
      tester,
    ) async {
      await openAddForm(tester);
      await tester.tap(find.byKey(const Key('close-transaction-form')));
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(discardDialogOpen(), isFalse);
    });

    testWidgets('form baru bersih: tap luar menutup tanpa konfirmasi', (
      tester,
    ) async {
      await openAddForm(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(discardDialogOpen(), isFalse);
    });

    testWidgets('form baru bersih: swipe-down menutup tanpa konfirmasi', (
      tester,
    ) async {
      await openAddForm(tester);
      await tester.fling(
        find.byKey(const Key('transaction-sheet-swipe-handle')),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(discardDialogOpen(), isFalse);
    });
  });

  // ── Dirty tracking ───────────────────────────────────────────────────────

  group('dirty tracking', () {
    testWidgets('transaksi baru: HANYA kategori berubah → dirty', (
      tester,
    ) async {
      await openAddForm(tester);
      await pickCategory(tester, 'Gaji');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      expect(sheetOpen(), isTrue);
      expect(repository.writes, 0);
    });

    testWidgets('transaksi baru: HANYA tanggal berubah → dirty', (
      tester,
    ) async {
      await openAddForm(tester);
      final now = DateTime.now();
      final target = DateTime(now.year, now.month, now.day == 15 ? 16 : 15);
      await pickDate(tester, target);
      // Pastikan tidak ada perubahan lain; tanggal tampil.
      expect(
        find.text(DateFormat('d MMMM yyyy', 'id_ID').format(target)),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      expect(sheetOpen(), isTrue);
      expect(repository.writes, 0);
    });

    testWidgets(
      'transaksi baru: kategori+tanggal saja, tanpa keterangan/jumlah → dirty',
      (tester) async {
        await openAddForm(tester);
        await pickCategory(tester, 'Makan & Minum');
        final now = DateTime.now();
        await pickDate(
          tester,
          DateTime(now.year, now.month, now.day == 10 ? 11 : 10),
        );
        await tester.tap(find.byKey(const Key('close-transaction-form')));
        await tester.pumpAndSettle();
        expect(discardDialogOpen(), isTrue);
      },
    );

    testWidgets(
      'cancel discard (Lanjut Edit) MENJAGA input kategori & tanggal',
      (tester) async {
        await openAddForm(tester);
        await pickCategory(tester, 'Gaji');
        final now = DateTime.now();
        final target = DateTime(now.year, now.month, now.day == 15 ? 16 : 15);
        await pickDate(tester, target);
        await tester.enterText(input('Keterangan'), 'Draft kategori & tanggal');
        await tester.pumpAndSettle();

        // Trigger dismissal (Back), lalu CANCEL discard.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(discardDialogOpen(), isTrue);
        await tester.tap(find.text('Lanjut Edit'));
        await tester.pumpAndSettle();

        // Sheet tetap, input tidak hilang tanpa keputusan.
        expect(sheetOpen(), isTrue);
        expect(discardDialogOpen(), isFalse);
        expect(
          tester.widget<TextField>(input('Keterangan')).controller!.text,
          'Draft kategori & tanggal',
        );
        expect(
          find.text(DateFormat('d MMMM yyyy', 'id_ID').format(target)),
          findsOneWidget,
        );
        // Kategori masih terpilih: simpan tetap bisa memakai 'Gaji'.
        expect(repository.writes, 0);
      },
    );

    testWidgets(
      'cancel discard pada kategori-only baru mempertahankan pilihan',
      (tester) async {
        await openAddForm(tester);
        await pickCategory(tester, 'Gaji');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lanjut Edit'));
        await tester.pumpAndSettle();
        expect(sheetOpen(), isTrue);
        // Isi sisanya lalu simpan memakai kategori yang tadi dipertahankan.
        await tester.enterText(input('Keterangan'), 'Gaji dipertahankan');
        await tester.enterText(input('Jumlah (Rp)'), '1000');
        await tester.pumpAndSettle();
        final save = find.widgetWithText(ElevatedButton, 'Tambah Transaksi');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repository.rows['A']!.single.category, 'Gaji');
        expect(repository.rows['A']!.single.isIncome, isTrue);
      },
    );

    testWidgets('discard disetujui (Buang) menutup form tanpa write', (
      tester,
    ) async {
      await openAddForm(tester);
      await pickCategory(tester, 'Gaji');
      await tester.enterText(input('Keterangan'), 'akan dibuang');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      await tester.tap(find.text('Buang'));
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(discardDialogOpen(), isFalse);
      expect(repository.writes, 0);
      expect(repository.rows['A'] ?? const [], isEmpty);
    });

    testWidgets('cancel discard via barrier pada dialog mempertahankan input', (
      tester,
    ) async {
      await openAddForm(tester);
      await tester.enterText(input('Keterangan'), 'tetap');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      // Barrier dialog ditutup → bukan discard.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(sheetOpen(), isTrue);
      expect(
        tester.widget<TextField>(input('Keterangan')).controller!.text,
        'tetap',
      );
    });
  });

  // ── Dismissal actual untuk dirty: 4 jalur sama-sama memakai guard ────────

  group('dirty dismissal actual', () {
    Future<void> makeDirty(WidgetTester tester) async {
      await pickCategory(tester, 'Gaji');
    }

    testWidgets('Back saat dirty → discard dialog; Buang menutup', (
      tester,
    ) async {
      await openAddForm(tester);
      await makeDirty(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      await tester.tap(find.text('Buang'));
      await tester.pumpAndSettle();
      expect(sheetOpen(), isFalse);
    });

    testWidgets('close button saat dirty → discard dialog', (tester) async {
      await openAddForm(tester);
      await makeDirty(tester);
      await tester.tap(find.byKey(const Key('close-transaction-form')));
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      expect(sheetOpen(), isTrue);
    });

    testWidgets('tap luar (barrier) saat dirty → discard dialog', (
      tester,
    ) async {
      await openAddForm(tester);
      await makeDirty(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(discardDialogOpen(), isTrue);
      expect(sheetOpen(), isTrue);
    });

    testWidgets(
      'swipe-down saat dirty → discard dialog (tidak melewati guard)',
      (tester) async {
        await openAddForm(tester);
        await makeDirty(tester);
        await tester.fling(
          find.byKey(const Key('transaction-sheet-swipe-handle')),
          const Offset(0, 300),
          1000,
        );
        await tester.pumpAndSettle();
        expect(discardDialogOpen(), isTrue);
        expect(sheetOpen(), isTrue);
      },
    );
  });
}

// ── Pending (state pending) dismissal & no-duplicate tests live alongside ──
// offline/pending retry in offline_sync_widget_test.dart.
