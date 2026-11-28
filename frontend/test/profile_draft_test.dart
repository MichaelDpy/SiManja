import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// A1-10 — Tentukan perlindungan draft profil (menutup A14 + A03).
///
/// Hanya menambah coverage yang BELUM ada: dirty/baseline; success memperbarui
/// baseline tanpa dialog dirty palsu; discard pada logout (cancel/batal vs
/// konfirmasi); pindah tab sendiri TIDAK menjebak & mempertahankan draft
/// (IndexedStack); logout karena sesi server invalid TIDAK ditahan draft;
/// perubahan UID tidak memindahkan draft/feedback A→B. Tidak mengubah
/// SessionController/AppState. Tes pending/submit-ganda/failure/conflict
/// profil existing tidak disentuh.
void main() {
  final state = AppState.instance;
  late MemoryProfiles profiles;
  late SessionAuth auth;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    profiles = MemoryProfiles();
    profiles.profiles['A'] = const UserProfile(
      name: 'Nama Server',
      city: 'Bandung',
      monthlyIncome: 5000000,
    );
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
    state.clearSession();
    state.useProfileRepository(profiles);
    state.useTransactionRepository(MemoryTransactions());
  });

  Finder field(String name) => find.descendant(
    of: find.byKey(Key('profile-$name')),
    matching: find.byType(TextFormField),
  );

  Future<void> pumpApp(WidgetTester tester) async {
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
        matching: find.text('Profil'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openLogoutDialog(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final logout = find.byKey(const Key('profile-logout'));
    await tester.ensureVisible(logout);
    await tester.tap(logout);
    await tester.pumpAndSettle();
  }

  // ── Dirty tracking / baseline ───────────────────────────────────────────

  testWidgets('form bersih (tanpa edit): logout tanpa catatan draft dibuang', (
    tester,
  ) async {
    await pumpApp(tester);
    await openLogoutDialog(tester);
    expect(find.text('Keluar dari Akun?'), findsOneWidget);
    expect(
      find.textContaining('Perubahan profil yang belum disimpan'),
      findsNothing,
    );
    // Batal: tidak keluar.
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('mengubah field → dirty; revert ke nilai baseline → clean lagi', (
    tester,
  ) async {
    await pumpApp(tester);
    final name = field('name');
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Nama A draft');
    await tester.pumpAndSettle();

    await openLogoutDialog(tester);
    expect(
      find.textContaining('Perubahan profil yang belum disimpan akan dibuang.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    // Kembalikan ke nilai baseline → clean (tidak ada discard note).
    await tester.enterText(name, 'Nama Server');
    await tester.pumpAndSettle();
    await openLogoutDialog(tester);
    expect(
      find.textContaining('Perubahan profil yang belum disimpan'),
      findsNothing,
    );
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'pendapatan: format vs nilai semantik; invalid pendapatan → dirty',
    (tester) async {
      await pumpApp(tester);
      final income = field('income');
      await tester.ensureVisible(income);
      // Baseline 5000000; '5.000.000' nilai sama → TIDAK dirty.
      await tester.enterText(income, '5.000.000');
      await tester.pumpAndSettle();
      await openLogoutDialog(tester);
      expect(
        find.textContaining('Perubahan profil yang belum disimpan'),
        findsNothing,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Pecahan invalid → dirty (draft berbeda; tidak bisa disimpan).
      await tester.enterText(income, '1,5');
      await tester.pumpAndSettle();
      await openLogoutDialog(tester);
      expect(
        find.textContaining(
          'Perubahan profil yang belum disimpan akan dibuang.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    },
  );

  // ── Success memperbarui baseline tanpa dialog dirty palsu ───────────────

  testWidgets(
    'success memperbarui baseline: setelah simpan tidak dirty palsu',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Nama Baru');
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Profil berhasil disimpan ke akun.'), findsOneWidget);
      expect(profiles.profiles['A']!.name, 'Nama Baru');

      // Setelah success, baseline baru; logout TANPA discard note palsu.
      await openLogoutDialog(tester);
      expect(
        find.textContaining('Perubahan profil yang belum disimpan'),
        findsNothing,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'gagal simpan mempertahankan input & tetap dirty; baseline tak berubah',
    (tester) async {
      await pumpApp(tester);
      profiles.saveFailure = StateError('offline');
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Nama Belum Tersimpan');
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      // Input dipertahankan; tidak ada sukses palsu; applied profil lama.
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Nama Belum Tersimpan',
      );
      expect(find.text('Profil berhasil disimpan ke akun.'), findsNothing);
      expect(profiles.profiles['A']!.name, 'Nama Server');

      // Tetap dirty → logout menampilkan discard note.
      await openLogoutDialog(tester);
      expect(
        find.textContaining(
          'Perubahan profil yang belum disimpan akan dibuang.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
    },
  );

  // ── Keputusan discard pada logout ───────────────────────────────────────

  testWidgets(
    'dirty + logout: Batal (cancel discard) menjaga input & tidak keluar',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft tidak hilang');
      await tester.pumpAndSettle();

      await openLogoutDialog(tester);
      expect(
        find.textContaining(
          'Perubahan profil yang belum disimpan akan dibuang.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsNothing);
      expect(state.sessionUid, 'A');
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Draft tidak hilang',
      );
    },
  );

  testWidgets(
    'dirty + logout: Keluar (discard disetujui) keluar & membersihkan sesi',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft dibuang');
      await tester.pumpAndSettle();

      await openLogoutDialog(tester);
      await tester.tap(find.byKey(const Key('confirm-logout')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(state.sessionUid, isNull);
    },
  );

  // ── Tidak menjebatkan navigasi ──────────────────────────────────────────

  testWidgets(
    'pindah tab sendiri tidak ditahan & tidak kehilangan draft (IndexedStack)',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft saat pindah tab');
      await tester.pumpAndSettle();

      // Pindah ke tab lain (tidak ada dialog discard!) lalu kembali.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Dasbor'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keluar dari Akun?'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Profil'),
        ),
      );
      await tester.pumpAndSettle();

      // Draft masih ada; halaman profil tidak ditutup.
      expect(field('name'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Draft saat pindah tab',
      );
    },
  );

  // ── Logout karena sesi server invalid tidak ditahan draft ───────────────

  testWidgets(
    'sesi server invalid (auth→null): logout paksa, tidak ditahan draft, tidak ada discard',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft saat sesi hangus');
      await tester.pumpAndSettle();

      // Server invalid → SessionController memancarkan null (BUKAN _logout).
      auth.emit(null);
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget); // tidak ditahan draft
      expect(
        find.text('Keluar dari Akun?'),
        findsNothing,
      ); // tidak ada discard dialog
      expect(state.sessionUid, isNull);
    },
  );

  // ── Perubahan UID tidak memindahkan draft/feedback A→B ──────────────────

  testWidgets(
    'UID switch A→B: draft A tidak pindah; tidak ada feedback A di B',
    (tester) async {
      await pumpApp(tester);
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft rahasia A');
      await tester.pumpAndSettle();

      // Ganti akun ke B (server-valid UID switch).
      profiles.profiles['B'] = const UserProfile(
        name: 'Nama B',
        city: 'Surabaya',
      );
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tester.pumpAndSettle();
      // MainShell dibuat ulang (UID keyed) → kembali ke tab Dasbor; pilih Profil.
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Profil'),
        ),
      );
      await tester.pumpAndSettle();

      // Draft A tidak pindah ke B; baseline B dari profil B.
      expect(find.text('Draft rahasia A'), findsNothing);
      expect(
        tester.widget<TextFormField>(field('name')).controller!.text,
        'Nama B',
      );
      // Tidak ada feedback sesi A (sukses/error/discard) di B.
      expect(find.text('Profil berhasil disimpan ke akun.'), findsNothing);
      expect(find.textContaining('Profil belum dapat disimpan'), findsNothing);
      expect(
        find.textContaining('Perubahan profil yang belum disimpan'),
        findsNothing,
      );
      expect(state.sessionUid, 'B');
    },
  );

  testWidgets(
    'UID switch saat save A pending: tidak ada write/feedback lanjut di B',
    (tester) async {
      await pumpApp(tester);
      profiles.pendingSave = Completer<void>();
      final name = field('name');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Draft A disimpan');
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump(); // save A pending

      // Ganti UID saat permintaan A berjalan.
      profiles.profiles['B'] = const UserProfile(name: 'Nama B');
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tester.pumpAndSettle();

      profiles.pendingSave!.complete();
      await tester.pumpAndSettle();

      // Tidak ada feedback sesi A di B; tidak ada draft A; profil B tidak diubah
      // oleh write A.
      expect(find.text('Profil berhasil disimpan ke akun.'), findsNothing);
      expect(find.textContaining('Profil belum dapat disimpan'), findsNothing);
      expect(find.text('Draft A disimpan'), findsNothing);
      expect(profiles.profiles['B']!.name, 'Nama B');
      expect(state.name, 'Nama B');
    },
  );
}
