import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/theme.dart';
import 'package:simanja/main.dart';
import 'package:simanja/screens/account_security_page.dart';
import 'package:simanja/screens/privacy_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// A1-18: pintu Profil ke Keamanan Akun dan Lisensi melalui SimanjaApp asli,
/// serta isi halaman Privasi yang sesuai kode.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });
  setUp(() {
    AppState.instance.clearSession();
    AppState.instance.useProfileRepository(MemoryProfiles());
    AppState.instance.useTransactionRepository(MemoryTransactions());
  });

  const userA = SessionUser(
    'A',
    'a@example.com',
    emailVerified: true,
    providerIds: [passwordProviderId],
  );

  Future<SessionAuth> openProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = SessionAuth(currentUser: userA);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await auth.events.close();
      AppState.instance.clearSession();
    });
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> tapEntry(WidgetTester tester, String key) async {
    final entry = find.byKey(Key(key));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  testWidgets('Profil membuka Keamanan Akun dan Back kembali ke Profil', (
    tester,
  ) async {
    await openProfile(tester);
    await tapEntry(tester, 'profile-security');

    expect(find.byType(AccountSecurityPage), findsOneWidget);
    expect(find.text('a@example.com'), findsOneWidget);
    expect(find.text('Email terverifikasi'), findsOneWidget);

    // AppBar menampilkan tombol kembali di layar.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byWidgetPredicate((w) => w is BackButton),
      ),
      findsOneWidget,
    );
    // Tombol Back sistem Android.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AccountSecurityPage), findsNothing);
    expect(find.byKey(const Key('profile-security')), findsOneWidget);
  });

  testWidgets('Profil membuka halaman lisensi yang memuat lisensi font', (
    tester,
  ) async {
    await openProfile(tester);
    await tapEntry(tester, 'profile-licenses');
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('SIMANJA'), findsWidgets);
  });

  testWidgets('ganti akun saat Keamanan Akun terbuka menutup halaman lama', (
    tester,
  ) async {
    final auth = await openProfile(tester);
    await tapEntry(tester, 'profile-security');
    expect(find.text('a@example.com'), findsOneWidget);

    auth.emit(
      const SessionUser(
        'B',
        'b@example.com',
        emailVerified: true,
        providerIds: [passwordProviderId],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AccountSecurityPage), findsNothing);
    expect(find.text('a@example.com'), findsNothing);
  });

  testWidgets(
    'logout dari Keamanan Akun tidak menyisakan halaman terlindungi',
    (tester) async {
      final auth = await openProfile(tester);
      await tapEntry(tester, 'profile-security');
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(AccountSecurityPage), findsNothing);
      expect(find.text('a@example.com'), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Privasi sesuai kode, tanpa klaim palsu (${dark ? 'gelap' : 'terang'})',
      (tester) async {
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: const PrivacyPage(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('dibundel di dalam aplikasi'),
          findsOneWidget,
        );
        expect(find.text('Google Sign-In'), findsOneWidget);
        expect(
          find.textContaining('tidak dapat ditarik kembali'),
          findsOneWidget,
        );
        expect(find.textContaining('bukan penghapusan aman'), findsOneWidget);
        expect(
          find.byKey(const Key('privacy-contact-pending')),
          findsOneWidget,
        );
        // Klaim yang tidak didukung kode tidak boleh muncul.
        for (final claim in [
          'diunduh dari Google Fonts',
          'Hubungi dukungan',
          'Hubungi tim',
          'end-to-end',
          'E2EE',
        ]) {
          expect(find.textContaining(claim), findsNothing, reason: claim);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
