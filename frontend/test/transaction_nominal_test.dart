// A1-01 — Regresi: jaga makna nominal dari field sampai mutasi
//
// Kriteria lulus (audit A01):
//   - Paste "100,50" tidak tersimpan sebagai 10050 (formatter menolak)
//   - Paste "-100" tidak tersimpan sebagai 100 (formatter menolak)
//   - "1.000,50" ditolak (koma = pecahan, FormatException)
//   - "1.2.3" ditolak (titik tidak konsisten)
//   - "1..000" ditolak (titik ganda)
//   - "0", batas+1 tidak memanggil repository.write
//   - "1000" menyimpan 1000 melalui repository
//   - "1.000" menyimpan 1000 melalui repository
//   - Nilai maksimum sah (9007199254740991) tersimpan utuh

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/screens/transaction_page.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _click(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Setup minimal: boot app ke layar transaksi dengan akun siap.
/// Kembalikan [MemoryTransactions] sebagai spy repository.
Future<MemoryTransactions> _boot(WidgetTester tester, SessionAuth auth) async {
  final profiles = MemoryProfiles();
  final transactions = MemoryTransactions();
  final state = AppState.instance..clearSession();
  state.useProfileRepository(profiles);
  state.useTransactionRepository(transactions);
  await tester.pumpWidget(SimanjaApp(initialRoute: '/login', auth: auth));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-email')), 'a@example.com');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'Password-uji123!',
  );
  await _click(tester, find.byKey(const Key('login-submit')));
  await _click(
    tester,
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Transaksi'),
    ),
  );
  return transactions;
}

/// Helper: buka sheet tambah transaksi dan isi keterangan + nominal.
Future<void> _openAndFillForm(
  WidgetTester tester, {
  required String nominal,
  String kategori = 'Gaji',
}) async {
  await _click(tester, find.byTooltip('Tambah Transaksi'));
  await tester.pumpAndSettle();
  await _click(tester, find.byType(DropdownButton<CategoryMeta>));
  await _click(tester, find.text(kategori).last);
  await tester.enterText(_input('Keterangan'), 'Uji nominal A1-01');
  await tester.enterText(_input('Jumlah (Rp)'), nominal);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  // ── 1. Unit parseRupiah ───────────────────────────────────────────────
  // parseRupiah adalah top-level function; diimport dari transaction_page.dart.

  group('A1-01 — parseRupiah: semua kasus batas domain', () {
    test('string kosong atau spasi dilempar FormatException', () {
      expect(() => parseRupiah(''), throwsA(isA<FormatException>()));
      expect(() => parseRupiah('   '), throwsA(isA<FormatException>()));
    });

    test('"0" dan bilangan di bawah 1 ditolak', () {
      expect(() => parseRupiah('0'), throwsA(isA<FormatException>()));
      expect(() => parseRupiah('00'), throwsA(isA<FormatException>()));
    });

    test('"1" dan nilai positif bulat diterima', () {
      expect(parseRupiah('1'), 1.0);
      expect(parseRupiah('1000'), 1000.0);
    });

    test('"1.000" (titik ribuan) diterima dan maknanya 1000', () {
      expect(parseRupiah('1.000'), 1000.0);
      expect(parseRupiah('1.500.000'), 1500000.0);
    });

    test('"1.000,50" (ada koma = pecahan) ditolak', () {
      expect(() => parseRupiah('1.000,50'), throwsA(isA<FormatException>()));
    });

    test('"100,50" (ada koma) ditolak', () {
      expect(() => parseRupiah('100,50'), throwsA(isA<FormatException>()));
    });

    test('"1.2.3" (grup titik bukan 3 digit) ditolak', () {
      expect(() => parseRupiah('1.2.3'), throwsA(isA<FormatException>()));
    });

    test('"1..000" (titik ganda = grup kosong) ditolak', () {
      expect(() => parseRupiah('1..000'), throwsA(isA<FormatException>()));
    });

    test('"1.23" (satu grup 2 digit setelah titik) ditolak', () {
      expect(() => parseRupiah('1.23'), throwsA(isA<FormatException>()));
    });

    test('"1.5" (grup 1 digit setelah titik) ditolak', () {
      expect(() => parseRupiah('1.5'), throwsA(isA<FormatException>()));
    });

    test('nilai maksimum sah (9007199254740991) diterima', () {
      expect(parseRupiah('9007199254740991'), 9007199254740991.0);
    });

    test('batas+1 (9007199254740992) ditolak', () {
      expect(
        () => parseRupiah('9007199254740992'),
        throwsA(isA<FormatException>()),
      );
    });

    test('karakter alfabet ditolak', () {
      expect(() => parseRupiah('abc'), throwsA(isA<FormatException>()));
      expect(() => parseRupiah('1abc'), throwsA(isA<FormatException>()));
    });
  });

  // ── 2. Formatter: paste dengan koma/minus tidak mengubah nilai ────────
  // testTextInput.updateEditingValue melewati jalur IME produksi yang
  // memanggil TextInputFormatter.formatEditUpdate secara nyata.

  group('A1-01 — formatter: karakter non-digit non-titik ditolak via IME', () {
    testWidgets('paste "100,50" ditolak formatter: field tetap kosong', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      await _boot(tester, auth);
      await _click(tester, find.byTooltip('Tambah Transaksi'));
      await tester.pumpAndSettle();

      // Fokus ke field nominal lalu simulasikan input IME dengan koma
      await tester.tap(_input('Jumlah (Rp)'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '100,50',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(_input('Jumlah (Rp)'));
      // Formatter menolak update (kembalikan oldValue = teks kosong)
      // sehingga "10050" tidak boleh muncul di controller
      expect(
        field.controller?.text,
        isNot(equals('10050')),
        reason:
            'Paste "100,50" tidak boleh tersimpan sebagai "10050": '
            'formatter menolak update, bukan strip koma secara diam-diam',
      );
      expect(
        field.controller?.text,
        equals(''),
        reason: 'Field harus tetap kosong setelah input dengan koma ditolak',
      );
    });

    testWidgets('paste "-100" ditolak formatter: field tetap kosong', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      await _boot(tester, auth);
      await _click(tester, find.byTooltip('Tambah Transaksi'));
      await tester.pumpAndSettle();

      await tester.tap(_input('Jumlah (Rp)'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '-100',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(_input('Jumlah (Rp)'));
      expect(
        field.controller?.text,
        isNot(equals('100')),
        reason:
            'Paste "-100" tidak boleh tersimpan sebagai "100": '
            'formatter menolak tanda minus, bukan membuangnya',
      );
      expect(
        field.controller?.text,
        equals(''),
        reason: 'Field harus tetap kosong setelah input dengan minus ditolak',
      );
    });

    testWidgets('"1.500.000" (digit + titik) diterima formatter', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      await _boot(tester, auth);
      await _click(tester, find.byTooltip('Tambah Transaksi'));
      await tester.pumpAndSettle();

      await tester.tap(_input('Jumlah (Rp)'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '1.500.000',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(_input('Jumlah (Rp)'));
      expect(
        field.controller?.text,
        equals('1.500.000'),
        reason: '"1.500.000" (digit + titik) harus diterima oleh formatter',
      );
    });
  });

  // ── 3. Submit: nilai sah → repository write; nilai invalid → tidak ────

  group('A1-01 — submit: repository spy memastikan makna dipertahankan', () {
    testWidgets('"1000" menyimpan amount=1000 melalui repository', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      final repo = await _boot(tester, auth);
      await _openAndFillForm(tester, nominal: '1000');
      await _click(
        tester,
        find.widgetWithText(ElevatedButton, 'Tambah Transaksi'),
      );

      expect(repo.writes, greaterThan(0));
      final saved = AppState.instance.transactions
          .where((tx) => tx.description == 'Uji nominal A1-01')
          .firstOrNull;
      expect(saved, isNotNull, reason: 'Transaksi harus tersimpan');
      expect(
        saved!.amount,
        1000.0,
        reason: '"1000" harus tersimpan sebagai 1000',
      );
    });

    testWidgets('"1.000" (titik ribuan) menyimpan amount=1000', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      final repo = await _boot(tester, auth);
      await _openAndFillForm(tester, nominal: '1.000');
      await _click(
        tester,
        find.widgetWithText(ElevatedButton, 'Tambah Transaksi'),
      );

      expect(repo.writes, greaterThan(0));
      final saved = AppState.instance.transactions
          .where((tx) => tx.description == 'Uji nominal A1-01')
          .firstOrNull;
      expect(saved, isNotNull);
      expect(
        saved!.amount,
        1000.0,
        reason: '"1.000" (titik ribuan) harus tersimpan sebagai 1000',
      );
    });

    testWidgets('"0" tidak memanggil repository.write', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      final repo = await _boot(tester, auth);
      final writesBefore = repo.writes;
      await _openAndFillForm(tester, nominal: '0');
      await _click(
        tester,
        find.widgetWithText(ElevatedButton, 'Tambah Transaksi'),
      );

      expect(
        repo.writes,
        writesBefore,
        reason: '"0" tidak boleh memanggil repository write',
      );
    });

    testWidgets('"1.000,50" tidak memanggil repository.write', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });

      final repo = await _boot(tester, auth);
      final writesBefore = repo.writes;
      // enterText melewati formatter, jadi kita perlu gunakan IME untuk ini
      await _click(tester, find.byTooltip('Tambah Transaksi'));
      await tester.pumpAndSettle();
      await _click(tester, find.byType(DropdownButton<CategoryMeta>));
      await _click(tester, find.text('Gaji').last);
      await tester.enterText(_input('Keterangan'), 'Uji nominal A1-01');
      // Fokus + IME untuk field nominal
      await tester.tap(_input('Jumlah (Rp)'));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '1.000,50',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      await _click(
        tester,
        find.widgetWithText(ElevatedButton, 'Tambah Transaksi'),
      );

      expect(
        repo.writes,
        writesBefore,
        reason: '"1.000,50" tidak boleh memanggil repository write',
      );
    });
  });
}
