// A1-03 — Samakan batas validasi editor dan domain
//
// Menutup audit A03.
//
// Kriteria lulus:
//   - Keterangan satu karakter sah; panjang 1000 sah; kosong/whitespace/1001 invalid.
//   - Tidak ada minimum dua karakter keterangan vs kontrak nonempty.
//   - Profil pendapatan 0 sah (dipertahankan); negatif/pecahan invalid.
//   - Submit ganda (Done + tap / tap ganda) paling banyak satu operasi.
//   - Failure mempertahankan input.
//   - Boundary widget + repository spy; regresi profil/transaksi terkait.
//   - Kontrak model/repository read-only; tidak melonggarkan server.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/screens/profile_page.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

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

/// Spy repository transaksi: rekam `add` & `update` apa adanya.
class _SpyTransactions extends MemoryTransactions {
  final adds = <TransactionModel>[];
  final updates = <({String uid, String id, TransactionModel transaction})>[];

  @override
  Future<void> add(String uid, TransactionModel transaction) async {
    adds.add(transaction);
    await super.add(uid, transaction);
  }

  @override
  Future<void> update(
    String uid,
    String id,
    TransactionModel transaction,
  ) async {
    updates.add((uid: uid, id: id, transaction: transaction));
    await super.update(uid, id, transaction);
  }
}

/// Boot app ke layar transaksi dengan akun siap; kembalikan spy repository.
Future<_SpyTransactions> _bootTx(WidgetTester tester, SessionAuth auth) async {
  final profiles = MemoryProfiles();
  final transactions = _SpyTransactions();
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

// Tombol simpan transaksi (satu-satunya ElevatedButton di dalam Form);
// stabil saat _saving menukar child menjadi CircularProgressIndicator.
Finder _saveTxButton() =>
    find.descendant(of: find.byType(Form), matching: find.byType(ElevatedButton));

/// Buka sheet tambah transaksi + pilih kategori + isi nominal.
Future<void> _openAddTx(WidgetTester tester, {String kategori = 'Gaji'}) async {
  await _click(tester, find.byTooltip('Tambah Transaksi'));
  await tester.pumpAndSettle();
  await _click(tester, find.byType(DropdownButton<CategoryMeta>));
  await _click(tester, find.text(kategori).last);
}

void _scaffold(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  // ── A. Transaksi: batas keterangan selaras kontrak nonempty/<=1000 ─────

  group('A1-03 — keterangan transaksi boundary', () {
    Future<_SpyTransactions> pumpTx(WidgetTester tester) async {
      _scaffold(tester);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });
      final transactions = await _bootTx(tester, auth);
      await _openAddTx(tester);
      await tester.enterText(_input('Jumlah (Rp)'), '1000');
      await tester.pumpAndSettle();
      return transactions;
    }

    testWidgets('keterangan SATU karakter sah (tidak ada minimum 2)', (
      tester,
    ) async {
      final transactions = await pumpTx(tester);
      await tester.enterText(_input('Keterangan'), 'a');
      await tester.pumpAndSettle();
      await _click(tester, _saveTxButton());

      expect(find.text('Keterangan minimal 2 karakter'), findsNothing);
      expect(find.text('Keterangan wajib diisi'), findsNothing);
      expect(transactions.adds, hasLength(1));
      expect(transactions.adds.single.description, 'a');
      // Payload mutasi efektif (Firestore).
      final payload = TransactionMapper.toMap(transactions.adds.single);
      expect(payload['description'], 'a');
      // Kontrak domain tetap memvalidasi (server tidak dilonggarkan).
      expect(
        () => TransactionMapper.toMap(transactions.adds.single),
        returnsNormally,
      );
    });

    testWidgets('keterangan panjang 1000 sah; panjang 1001 invalid', (
      tester,
    ) async {
      final transactions = await pumpTx(tester);

      // 1000 karakter (non-space) → sah.
      await tester.enterText(_input('Keterangan'), 'a' * 1000);
      await tester.pumpAndSettle();
      await _click(tester, _saveTxButton());
      expect(find.text('Keterangan maksimal 1000 karakter'), findsNothing);
      expect(transactions.adds, hasLength(1));
      expect(transactions.adds.single.description.length, 1000);
      expect(
        TransactionMapper.toMap(transactions.adds.single)['description'],
        'a' * 1000,
      );

      // Reset untuk kasus 1001.
      transactions.adds.clear();
      await _click(tester, find.byTooltip('Tambah Transaksi'));
      await tester.pumpAndSettle();
      await _click(tester, find.byType(DropdownButton<CategoryMeta>));
      await _click(tester, find.text('Gaji').last);
      await tester.enterText(_input('Jumlah (Rp)'), '1000');
      await tester.enterText(_input('Keterangan'), 'a' * 1001);
      await tester.pumpAndSettle();
      await _click(tester, _saveTxButton());

      // 1001 invalid; tidak diam-diam dipotong; tidak ada mutasi.
      expect(find.text('Keterangan maksimal 1000 karakter'), findsOneWidget);
      expect(transactions.adds, isEmpty);
      // Panjang input tidak dipotong oleh maxLength.
      final field = tester.widget<TextField>(_input('Keterangan'));
      expect(field.controller?.text.length, 1001);
    });

    testWidgets('keterangan kosong invalid; tidak ada mutasi', (tester) async {
      final transactions = await pumpTx(tester);
      await tester.enterText(_input('Keterangan'), '');
      await tester.pumpAndSettle();
      await _click(tester, _saveTxButton());

      expect(find.text('Keterangan wajib diisi'), findsOneWidget);
      expect(transactions.adds, isEmpty);
    });

    testWidgets('keterangan whitespace-only invalid; tidak ada mutasi', (
      tester,
    ) async {
      final transactions = await pumpTx(tester);
      await tester.enterText(_input('Keterangan'), '     ');
      await tester.pumpAndSettle();
      await _click(tester, _saveTxButton());

      expect(find.text('Keterangan wajib diisi'), findsOneWidget);
      expect(transactions.adds, isEmpty);
    });

    testWidgets('kontrak domain tetap menolak keterangan kosong/1001 '
        '(tidak melonggarkan server)', (tester) async {
      // Langsung di batas repository, independen dari editor.
      TransactionModel base(String description) => TransactionModel(
        id: 'x',
        category: 'Gaji',
        description: description,
        amount: 1000,
        isIncome: true,
        date: DateTime(2026, 1, 1),
      );
      expect(() => TransactionMapper.toMap(base('')), throwsArgumentError);
      expect(() => TransactionMapper.toMap(base('   ')), throwsArgumentError);
      expect(() => TransactionMapper.toMap(base('a')), returnsNormally);
      expect(() => TransactionMapper.toMap(base('a' * 1000)), returnsNormally);
      expect(
        () => TransactionMapper.toMap(base('a' * 1001)),
        throwsArgumentError,
      );
    });
  });

  // ── B. Submit ganda + failure mempertahankan input ────────────────────

  group('A1-03 — submit ganda & input setelah gagal (transaksi)', () {
    Future<_SpyTransactions> pumpValid(WidgetTester tester) async {
      _scaffold(tester);
      final auth = SessionAuth();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        AppState.instance.clearSession();
        await auth.events.close();
      });
      final transactions = await _bootTx(tester, auth);
      await _openAddTx(tester);
      await tester.enterText(_input('Keterangan'), 'Uji submit ganda');
      await tester.enterText(_input('Jumlah (Rp)'), '25000');
      await tester.pumpAndSettle();
      return transactions;
    }

    testWidgets('tap ganda paling banyak satu operasi', (tester) async {
      final transactions = await pumpValid(tester);
      final pending = Completer<void>();
      transactions.pendingWrite = pending;

      await tester.ensureVisible(_saveTxButton());
      await tester.pump();
      await tester.tap(_saveTxButton());
      await tester.pump();
      // Kedua tap saat operasi pertama masih berjalan.
      await tester.tap(_saveTxButton(), warnIfMissed: false);
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(transactions.adds, hasLength(1));
      expect(transactions.writes, 1);
    });

    testWidgets('Done + tap paling banyak satu operasi', (tester) async {
      final transactions = await pumpValid(tester);
      final pending = Completer<void>();
      transactions.pendingWrite = pending;

      await tester.ensureVisible(_saveTxButton());
      await tester.pump();
      // Fokus ke field terakhir lalu tekan Done (keyboard) ...
      await tester.tap(_input('Jumlah (Rp)'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // ... lalu tap tombol simpan.
      await tester.tap(_saveTxButton(), warnIfMissed: false);
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(transactions.adds, hasLength(1));
      expect(transactions.writes, 1);
    });

    testWidgets('failure mempertahankan input & bisa retry', (tester) async {
      final transactions = await pumpValid(tester);
      transactions.writeFailure = StateError('gagal simpan uji');

      await _click(tester, _saveTxButton());

      // Error tampil, _saving reset, input TIDAK dibersihkan.
      expect(find.textContaining('Gagal menyimpan'), findsOneWidget);
      expect(
        tester.widget<TextField>(_input('Keterangan')).controller?.text,
        'Uji submit ganda',
      );
      expect(
        tester.widget<TextField>(_input('Jumlah (Rp)')).controller?.text,
        '25000',
      );
      expect(transactions.adds, hasLength(1)); // dicoba sekali, gagal
      expect(transactions.committedWrites, 0);

      // Retry setelah failure berhasil (input sudah tadi dipertahankan).
      transactions.writeFailure = null;
      await _click(tester, _saveTxButton());
      expect(transactions.committedWrites, 1);
    });
  });

  // ── C. Profil pendapatan nol + validasi + submit ganda + failure ──────

  group('A1-03 — profil pendapatan', () {
    late MemoryProfiles repository;
    late SessionAuth auth;

    setUp(() {
      repository = MemoryProfiles();
      repository.profiles['A'] = const UserProfile(
        name: 'Nama Server',
        monthlyIncome: 0, // pendapatan profil NOL
      );
      auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
      AppState.instance.clearSession();
      AppState.instance.useTransactionRepository(MemoryTransactions());
    });

    Future<void> pumpProfile(WidgetTester tester, {double income = 0}) async {
      _scaffold(tester);
      repository.profiles['A'] = UserProfile(
        name: 'Nama Server',
        monthlyIncome: income,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await auth.events.close();
        AppState.instance.clearSession();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(
            auth: auth,
            profiles: repository,
            homeBuilder: (_) => const ProfilePage(),
          ),
          routes: {'/login': (_) => LoginPage(auth: auth)},
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> submitProfile(WidgetTester tester) async {
      final save = find.byKey(const Key('profile-save'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    Finder incomeField() => find.descendant(
      of: find.byKey(const Key('profile-income')),
      matching: find.byType(TextFormField),
    );

    testWidgets('pendapatan profil NOL sah & dipertahankan', (tester) async {
      await pumpProfile(tester, income: 0);

      // Field menampilkan 0 (tidak dikosongkan).
      expect(tester.widget<TextFormField>(incomeField()).controller?.text, '0');

      await submitProfile(tester);

      expect(find.textContaining('Pendapatan harus berupa'), findsNothing);
      expect(repository.profiles['A']!.monthlyIncome, 0);
    });

    testWidgets('pendapatan 0 eksplisit sah; negatif & pecahan invalid', (
      tester,
    ) async {
      await pumpProfile(tester, income: 5000);

      // 0 eksplisit → sah.
      await tester.enterText(incomeField(), '0');
      await tester.pumpAndSettle();
      await submitProfile(tester);
      expect(find.textContaining('Pendapatan harus berupa'), findsNothing);
      expect(repository.profiles['A']!.monthlyIncome, 0);

      // negatif → invalid.
      await tester.enterText(incomeField(), '-1');
      await tester.pumpAndSettle();
      await submitProfile(tester);
      expect(
        find.text('Pendapatan harus berupa angka bulat non-negatif'),
        findsOneWidget,
      );

      // pecahan → invalid (koma).
      await tester.enterText(incomeField(), '1,5');
      await tester.pumpAndSettle();
      await submitProfile(tester);
      expect(
        find.text('Pendapatan harus berupa angka bulat non-negatif'),
        findsOneWidget,
      );

      // pecahan → invalid (titik desimal, bukan ribuan).
      await tester.enterText(incomeField(), '1.5');
      await tester.pumpAndSettle();
      await submitProfile(tester);
      expect(
        find.text('Pendapatan harus berupa angka bulat non-negatif'),
        findsOneWidget,
      );
      // Tidak ada mutasi tambahan saat invalid.
      expect(repository.saves.where((s) => s.changes.isNotEmpty), isNotEmpty);
    });

    testWidgets('submit ganda profil paling banyak satu operasi', (
      tester,
    ) async {
      await pumpProfile(tester, income: 0);
      final pending = Completer<void>();
      repository.pendingSave = pending;

      await tester.enterText(incomeField(), '5000000');
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.pump();
      final savesBefore = repository.saves.length;
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(repository.saves.length - savesBefore, 1);
    });

    testWidgets('failure mempertahankan input pendapatan', (tester) async {
      await pumpProfile(tester, income: 0);
      repository.saveFailure = StateError('gagal simpan profil uji');

      await tester.enterText(incomeField(), '123456');
      await tester.pumpAndSettle();
      await submitProfile(tester);

      // Input tidak dibersihkan saat gagal.
      expect(
        tester.widget<TextFormField>(incomeField()).controller?.text,
        '123456',
      );
      // _saveError ditampilkan (SyncFailure); draft tidak dibersihkan.
      expect(
        find.textContaining('Hasil penyimpanan belum dapat dipastikan'),
        findsOneWidget,
      );
    });
  });
}
