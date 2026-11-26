import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/firebase_environment.dart';
import 'package:simanja/screens/account_security_page.dart';
import 'package:simanja/screens/login_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/session_auth.dart';

/// B06–B08: login Google, menghubungkan metode ke UID sama, dan melepas
/// metode tanpa mengunci akun.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  const passwordUser = SessionUser(
    'A',
    'a@example.com',
    emailVerified: true,
    providerIds: [passwordProviderId],
  );

  // ── B06 login Google ────────────────────────────────────────────────────
  group('B06 login Google', () {
    Future<void> pumpLogin(WidgetTester tester, SessionAuth auth) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(auth: auth),
          routes: {'/home': (_) => const Scaffold(body: Text('Home tes'))},
        ),
      );
    }

    Future<void> tapGoogle(WidgetTester tester) async {
      final button = find.byKey(const Key('login-google'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
    }

    testWidgets('tidak ditawarkan bila belum dikonfigurasi', (tester) async {
      await pumpLogin(tester, SessionAuth());
      expect(find.byKey(const Key('login-google')), findsNothing);
    });

    testWidgets('berhasil hanya setelah layanan selesai, tanpa tap ganda', (
      tester,
    ) async {
      final auth = SessionAuth()
        ..googleSignInAvailable = true
        ..pendingGoogle = Completer<void>();
      await pumpLogin(tester, auth);
      await tapGoogle(tester);
      expect(find.text('Menghubungkan ke Google…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('login-google')))
            .onPressed,
        isNull,
      );
      expect(find.text('Home tes'), findsNothing);
      auth.pendingGoogle!.complete();
      await tester.pumpAndSettle();
      expect(auth.googleCalls, ['signIn']);
      expect(find.text('Home tes'), findsOneWidget);
    });

    testWidgets('batal memilih akun: tetap di login tanpa pesan error', (
      tester,
    ) async {
      final auth = SessionAuth()
        ..googleSignInAvailable = true
        ..googleEmail = null;
      await pumpLogin(tester, auth);
      await tapGoogle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Dibatalkan.'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('login-google')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('email sudah terdaftar metode lain: tidak digabung otomatis', (
      tester,
    ) async {
      final auth = SessionAuth()
        ..googleSignInAvailable = true
        ..googleFailure = FirebaseAuthException(
          code: 'account-exists-with-different-credential',
        );
      await pumpLogin(tester, auth);
      await tapGoogle(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('hubungkan Google'), findsOneWidget);
      expect(find.text('Home tes'), findsNothing);
    });

    testWidgets('provider nonaktif / offline dijelaskan', (tester) async {
      final auth = SessionAuth()
        ..googleSignInAvailable = true
        ..googleFailure = FirebaseAuthException(code: 'operation-not-allowed');
      await pumpLogin(tester, auth);
      await tapGoogle(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('belum diaktifkan'), findsOneWidget);

      auth.googleFailure = FirebaseAuthException(
        code: 'network-request-failed',
      );
      await tapGoogle(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Koneksi gagal'), findsOneWidget);
    });

    test('client ID Google divalidasi oleh config lingkungan', () {
      expect(
        FirebaseEnvironmentConfig.resolve(
          googleServerClientId:
              '123456789012-abcdef0123456789.apps.googleusercontent.com',
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ).googleServerClientId,
        '123456789012-abcdef0123456789.apps.googleusercontent.com',
      );
      expect(
        () => FirebaseEnvironmentConfig.resolve(
          googleServerClientId: 'ISI_WEB_CLIENT_ID',
          platform: FirebaseAppPlatform.android,
          releaseBuild: false,
        ),
        throwsA(isA<FirebaseConfigException>()),
      );
    });
  });

  // ── B08 aturan anti-lockout ─────────────────────────────────────────────
  group('B08 unlinkBlockReason', () {
    test('satu-satunya metode tidak boleh dilepas', () {
      expect(
        unlinkBlockReason(
          [passwordProviderId],
          passwordProviderId,
          googleAvailable: true,
        ),
        contains('satu-satunya'),
      );
    });

    test('metode yang tidak terhubung ditolak', () {
      expect(
        unlinkBlockReason(
          [passwordProviderId],
          googleProviderId,
          googleAvailable: true,
        ),
        'Metode ini tidak terhubung.',
      );
    });

    test('password tersisa selalu aman', () {
      expect(
        unlinkBlockReason(
          [passwordProviderId, googleProviderId],
          googleProviderId,
          googleAvailable: false,
        ),
        isNull,
      );
    });

    test('Google tersisa hanya aman bila bisa dipakai di perangkat ini', () {
      final providers = [passwordProviderId, googleProviderId];
      expect(
        unlinkBlockReason(providers, passwordProviderId, googleAvailable: true),
        isNull,
      );
      expect(
        unlinkBlockReason(
          providers,
          passwordProviderId,
          googleAvailable: false,
        ),
        contains('belum bisa dipakai'),
      );
    });

    test('provider lain yang belum didukung tidak dihitung', () {
      expect(
        unlinkBlockReason(
          [passwordProviderId, 'apple.com'],
          passwordProviderId,
          googleAvailable: true,
        ),
        contains('belum bisa dipakai'),
      );
    });
  });

  // ── B07/B08 di halaman Keamanan Akun ────────────────────────────────────
  Future<void> pumpSecurity(WidgetTester tester, SessionAuth auth) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AccountSecurityPage(auth: auth)));
    await tester.pumpAndSettle();
  }

  Future<void> reauthWithPassword(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('reauth-password')),
      'Password123!',
    );
    await tester.tap(find.byKey(const Key('reauth-submit')));
    await tester.pumpAndSettle();
  }

  group('B07 menghubungkan metode ke UID yang sama', () {
    testWidgets('Google belum dikonfigurasi tidak ditawarkan aktif', (
      tester,
    ) async {
      await pumpSecurity(tester, SessionAuth(currentUser: passwordUser));
      expect(find.byKey(const Key('link-google')), findsNothing);
      expect(find.text('Google belum tersedia'), findsOneWidget);
    });

    testWidgets('akun email menghubungkan Google; UID tetap', (tester) async {
      final auth = SessionAuth(currentUser: passwordUser)
        ..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      await tester.tap(find.byKey(const Key('link-google')));
      await tester.pumpAndSettle();
      await reauthWithPassword(tester);

      expect(auth.reauthCalls, [SensitiveOperation.linkProvider]);
      expect(auth.currentUser!.uid, 'A');
      expect(auth.currentUser!.providerIds, [
        passwordProviderId,
        googleProviderId,
      ]);
      expect(find.byKey(const Key('provider-google.com')), findsOneWidget);
      expect(find.textContaining('Data akun tetap sama'), findsOneWidget);
    });

    testWidgets('Google milik UID lain: ditolak, tidak digabung', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: passwordUser)
        ..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      auth.googleFailure = FirebaseAuthException(
        code: 'credential-already-in-use',
      );
      await tester.tap(find.byKey(const Key('link-google')));
      await tester.pumpAndSettle();
      await reauthWithPassword(tester);

      expect(find.textContaining('tidak digabung otomatis'), findsOneWidget);
      expect(auth.currentUser!.providerIds, [passwordProviderId]);
      expect(auth.currentUser!.uid, 'A');
    });

    testWidgets('batal reauth: tidak ada penghubungan', (tester) async {
      final auth = SessionAuth(currentUser: passwordUser)
        ..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      await tester.tap(find.byKey(const Key('link-google')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reauth-cancel')));
      await tester.pumpAndSettle();
      expect(auth.googleCalls, isEmpty);
      expect(auth.currentUser!.providerIds, [passwordProviderId]);
    });

    testWidgets('akun Google menambah password lewat reauth Google', (
      tester,
    ) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'G',
          'g@gmail.com',
          emailVerified: true,
          providerIds: [googleProviderId],
        ),
      )..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      expect(find.byKey(const Key('security-change-password')), findsNothing);

      await tester.tap(find.byKey(const Key('link-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('link-password-new')),
        'PasswordBaru1!',
      );
      await tester.enterText(
        find.byKey(const Key('link-password-confirm')),
        'PasswordBaru1!',
      );
      await tester.tap(find.byKey(const Key('link-password-submit')));
      await tester.pumpAndSettle();

      // Akun Google tidak diminta password yang tidak dimilikinya.
      expect(find.byKey(const Key('reauth-password')), findsNothing);
      await tester.tap(find.byKey(const Key('reauth-google')));
      await tester.pumpAndSettle();

      expect(auth.currentUser!.uid, 'G');
      expect(auth.currentUser!.providerIds, [
        googleProviderId,
        passwordProviderId,
      ]);
      expect(auth.validPassword, 'PasswordBaru1!');
    });
  });

  group('B08 melepas metode tanpa lockout', () {
    testWidgets('satu metode: tombol Lepas tidak ada', (tester) async {
      await pumpSecurity(tester, SessionAuth(currentUser: passwordUser));
      expect(find.byKey(const Key('unlink-password')), findsNothing);
    });

    testWidgets('dua metode: lepas Google setelah konfirmasi dan reauth', (
      tester,
    ) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          emailVerified: true,
          providerIds: [passwordProviderId, googleProviderId],
        ),
      )..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      await tester.tap(find.byKey(const Key('unlink-google.com')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unlink-confirm')));
      await tester.pumpAndSettle();
      await reauthWithPassword(tester);

      expect(auth.unlinked, [googleProviderId]);
      expect(auth.currentUser!.providerIds, [passwordProviderId]);
      expect(find.byKey(const Key('provider-google.com')), findsNothing);
      expect(find.byKey(const Key('unlink-password')), findsNothing);
    });

    testWidgets('pengganti belum bisa dipakai: ditolak sebelum reauth', (
      tester,
    ) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          emailVerified: true,
          providerIds: [passwordProviderId, googleProviderId],
        ),
      ); // Google tidak tersedia di perangkat ini.
      await pumpSecurity(tester, auth);
      await tester.tap(find.byKey(const Key('unlink-password')));
      await tester.pumpAndSettle();

      expect(find.textContaining('belum bisa dipakai'), findsOneWidget);
      expect(find.byKey(const Key('unlink-confirm')), findsNothing);
      expect(auth.reauthCalls, isEmpty);
      expect(auth.unlinked, isEmpty);
    });

    testWidgets('batal konfirmasi: tidak ada perubahan', (tester) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          emailVerified: true,
          providerIds: [passwordProviderId, googleProviderId],
        ),
      )..googleSignInAvailable = true;
      await pumpSecurity(tester, auth);
      await tester.tap(find.byKey(const Key('unlink-google.com')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(auth.reauthCalls, isEmpty);
      expect(auth.unlinked, isEmpty);
    });

    test('grant milik operasi lain tidak bisa dipakai untuk unlink', () async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          providerIds: [passwordProviderId, googleProviderId],
        ),
      )..googleSignInAvailable = true;
      final grant = await auth.reauthenticateWithPassword(
        'Password123!',
        SensitiveOperation.linkProvider,
      );
      await expectLater(
        auth.unlinkProvider(grant, googleProviderId),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCodes.reauthMismatch,
          ),
        ),
      );
      expect(auth.unlinked, isEmpty);
    });
  });
}
