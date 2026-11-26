import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/screens/account_security_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/session_auth.dart';

/// B05: kontrak recent-login dan pusat keamanan akun.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  const user = SessionUser(
    'A',
    'a@example.com',
    emailVerified: true,
    providerIds: ['password'],
  );

  group('ReauthGrant terikat UID, operasi, dan waktu', () {
    final at = DateTime(2026, 11, 26, 10);
    final grant = ReauthGrant(
      uid: 'A',
      operation: SensitiveOperation.changePassword,
      grantedAt: at,
    );

    test('berlaku untuk UID dan operasi yang sama dalam 5 menit', () {
      expect(
        grant.allows(
          'A',
          SensitiveOperation.changePassword,
          now: at.add(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test('ditolak untuk UID lain, operasi lain, atau kedaluwarsa', () {
      expect(
        grant.allows('B', SensitiveOperation.changePassword, now: at),
        isFalse,
      );
      expect(
        grant.allows('A', SensitiveOperation.deleteAccount, now: at),
        isFalse,
      );
      expect(
        grant.allows(
          'A',
          SensitiveOperation.changePassword,
          now: at.add(const Duration(minutes: 5, seconds: 1)),
        ),
        isFalse,
      );
    });
  });

  Future<void> pumpPage(WidgetTester tester, SessionAuth auth) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountSecurityPage(auth: auth),
        routes: {'/login': (_) => const Scaffold(body: Text('Login tes'))},
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openChangePassword(
    WidgetTester tester, {
    String newPassword = 'PasswordBaru1!',
    String? confirm,
  }) async {
    await tester.tap(find.byKey(const Key('security-change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('change-new')), newPassword);
    await tester.enterText(
      find.byKey(const Key('change-confirm')),
      confirm ?? newPassword,
    );
    await tester.tap(find.byKey(const Key('change-submit')));
    await tester.pumpAndSettle();
  }

  group('pusat keamanan', () {
    testWidgets('menampilkan data Auth: email, verifikasi, metode masuk', (
      tester,
    ) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          providerIds: ['password', 'google.com'],
        ),
      );
      await pumpPage(tester, auth);
      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.text('Email belum diverifikasi'), findsOneWidget);
      expect(find.text('Email & password, Google'), findsOneWidget);

      auth.serverEmailVerified = true;
      await tester.tap(find.byKey(const Key('security-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('Email terverifikasi'), findsOneWidget);
    });

    testWidgets('tanpa sesi menampilkan ajakan masuk', (tester) async {
      await pumpPage(tester, SessionAuth());
      expect(
        find.text('Sesi berakhir. Silakan masuk kembali.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('Login tes'), findsOneWidget);
    });

    testWidgets('akun tanpa password tidak ditawari ganti password', (
      tester,
    ) async {
      await pumpPage(
        tester,
        SessionAuth(
          currentUser: const SessionUser(
            'G',
            'g@example.com',
            emailVerified: true,
            providerIds: ['google.com'],
          ),
        ),
      );
      expect(find.byKey(const Key('security-change-password')), findsNothing);
      expect(find.text('Ganti password tidak tersedia'), findsOneWidget);
    });
  });

  group('ganti password lewat autentikasi ulang', () {
    testWidgets('password benar → reauth lalu password diganti', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user);
      await pumpPage(tester, auth);
      await openChangePassword(tester);

      expect(find.byKey(const Key('reauth-password')), findsOneWidget);
      expect(auth.passwordChanges, isEmpty);
      await tester.enterText(
        find.byKey(const Key('reauth-password')),
        'Password123!',
      );
      await tester.tap(find.byKey(const Key('reauth-submit')));
      await tester.pumpAndSettle();

      expect(auth.reauthCalls, [SensitiveOperation.changePassword]);
      expect(auth.passwordChanges, ['PasswordBaru1!']);
      expect(find.textContaining('Password berhasil diganti'), findsOneWidget);
    });

    testWidgets('batal verifikasi ulang → operasi sensitif tidak dijalankan', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user);
      await pumpPage(tester, auth);
      await openChangePassword(tester);
      await tester.tap(find.byKey(const Key('reauth-cancel')));
      await tester.pumpAndSettle();

      expect(auth.passwordChanges, isEmpty);
      expect(find.text('Dibatalkan. Password tidak diubah.'), findsOneWidget);
      expect(find.textContaining('berhasil'), findsNothing);
    });

    testWidgets('password salah → tetap di dialog, tidak ada perubahan', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user);
      await pumpPage(tester, auth);
      await openChangePassword(tester);
      await tester.enterText(find.byKey(const Key('reauth-password')), 'salah');
      await tester.tap(find.byKey(const Key('reauth-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Email atau password salah.'), findsOneWidget);
      expect(find.byKey(const Key('reauth-password')), findsOneWidget);
      expect(auth.passwordChanges, isEmpty);
    });

    testWidgets('offline saat reauth → pesan koneksi, tidak ada perubahan', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user)
        ..reauthFailure = FirebaseAuthException(code: 'network-request-failed');
      await pumpPage(tester, auth);
      await openChangePassword(tester);
      await tester.enterText(
        find.byKey(const Key('reauth-password')),
        'Password123!',
      );
      await tester.tap(find.byKey(const Key('reauth-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Koneksi gagal'), findsOneWidget);
      expect(auth.passwordChanges, isEmpty);
    });

    testWidgets('password baru terlalu pendek tidak membuka reauth', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user);
      await pumpPage(tester, auth);
      await openChangePassword(tester, newPassword: '123');
      expect(find.textContaining('Minimal 6 karakter'), findsOneWidget);
      expect(find.byKey(const Key('reauth-password')), findsNothing);
      expect(auth.reauthCalls, isEmpty);
    });

    testWidgets('server menolak update (recent login kedaluwarsa) → jujur', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user)
        ..changePasswordFailure = FirebaseAuthException(
          code: 'requires-recent-login',
        );
      await pumpPage(tester, auth);
      await openChangePassword(tester);
      await tester.enterText(
        find.byKey(const Key('reauth-password')),
        'Password123!',
      );
      await tester.tap(find.byKey(const Key('reauth-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('masukkan ulang password'), findsOneWidget);
      expect(find.textContaining('berhasil'), findsNothing);
    });

    testWidgets('halaman ditutup saat reauth berjalan tidak error', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: user)
        ..pendingReauth = Completer<void>();
      await pumpPage(tester, auth);
      await openChangePassword(tester);
      await tester.enterText(
        find.byKey(const Key('reauth-password')),
        'Password123!',
      );
      await tester.tap(find.byKey(const Key('reauth-submit')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      auth.pendingReauth!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(auth.passwordChanges, isEmpty);
    });

    test('grant milik operasi lain ditolak oleh changePassword', () async {
      final auth = SessionAuth(currentUser: user);
      final grant = await auth.reauthenticateWithPassword(
        'Password123!',
        SensitiveOperation.deleteAccount,
      );
      await expectLater(
        auth.changePassword(grant, 'PasswordBaru1!'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCodes.reauthMismatch,
          ),
        ),
      );
      expect(auth.passwordChanges, isEmpty);
    });
  });
}
