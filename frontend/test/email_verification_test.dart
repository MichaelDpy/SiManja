import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/session_controller.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/services/auth_service.dart';
import 'package:simanja/widgets/email_verification_banner.dart';
import 'package:simanja/widgets/session_scope.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// B04: status verifikasi email mengikuti server Auth, dengan kirim ulang,
/// cooldown, periksa ulang, dan pergantian akun.
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

  const unverified = SessionUser('A', 'a@example.com');

  Future<void> pumpGate(WidgetTester tester, SessionAuth auth) async {
    Widget gate() => SessionGate(
      auth: auth,
      homeBuilder: (context) => Scaffold(
        body: Text('Home ${SessionScope.maybeOf(context)!.user!.uid}'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: gate(),
        // Seperti aplikasi: pergantian UID membangun ulang stack ke /home.
        routes: {'/home': (_) => gate(), '/login': (_) => const Text('Login')},
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cleanup(WidgetTester tester, SessionAuth auth) async {
    await tester.pumpWidget(const SizedBox());
    await auth.events.close();
  }

  group('kapan banner tampil', () {
    test('hanya akun password dengan email yang belum terverifikasi', () {
      expect(needsEmailVerification(unverified), isTrue);
      expect(needsEmailVerification(null), isFalse);
      expect(
        needsEmailVerification(
          const SessionUser('A', 'a@example.com', emailVerified: true),
        ),
        isFalse,
      );
      expect(
        needsEmailVerification(
          const SessionUser('A', 'a@example.com', providerIds: ['google.com']),
        ),
        isFalse,
        reason: 'Akun Google sudah diverifikasi oleh penyedia',
      );
    });

    testWidgets('akun belum terverifikasi melihat banner, Home tetap terbuka', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified);
      await pumpGate(tester, auth);
      expect(find.byType(EmailVerificationBanner), findsOneWidget);
      expect(find.text('Home A'), findsOneWidget);
      await cleanup(tester, auth);
    });

    testWidgets('akun terverifikasi tidak melihat banner', (tester) async {
      final auth = SessionAuth(
        currentUser: const SessionUser(
          'A',
          'a@example.com',
          emailVerified: true,
        ),
      );
      await pumpGate(tester, auth);
      expect(find.byType(EmailVerificationBanner), findsNothing);
      await cleanup(tester, auth);
    });
  });

  group('kirim tautan', () {
    testWidgets('kirim sekali, lalu cooldown mencegah kirim ganda', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified)
        ..pendingVerification = Completer<void>();
      await pumpGate(tester, auth);

      await tester.tap(find.byKey(const Key('verify-send')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('verify-send')));
      await tester.pump();
      expect(find.text('Mengirim…'), findsOneWidget);

      auth.pendingVerification!.complete();
      await tester.pump();
      expect(auth.verificationsSent, 1);
      expect(find.textContaining('Auth Emulator'), findsOneWidget);
      expect(find.text('Kirim ulang (60d)'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('verify-send')))
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Kirim tautan'), findsOneWidget);
      await cleanup(tester, auth);
    });

    testWidgets('gagal kirim tidak mengklaim terkirim dan tanpa cooldown', (
      tester,
    ) async {
      final auth = SessionAuth(
        currentUser: unverified,
      )..verificationFailure = FirebaseAuthException(code: 'too-many-requests');
      await pumpGate(tester, auth);
      await tester.tap(find.byKey(const Key('verify-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Terlalu banyak percobaan'), findsOneWidget);
      expect(find.textContaining('dikirim'), findsNothing);
      expect(find.text('Kirim tautan'), findsOneWidget);
      await cleanup(tester, auth);
    });
  });

  group('periksa status', () {
    testWidgets('server masih belum terverifikasi → pesan jujur', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified);
      await pumpGate(tester, auth);
      await tester.tap(find.byKey(const Key('verify-check')));
      await tester.pumpAndSettle();
      expect(auth.reloads, 1);
      expect(find.textContaining('belum terverifikasi'), findsOneWidget);
      expect(find.byType(EmailVerificationBanner), findsOneWidget);
      await cleanup(tester, auth);
    });

    testWidgets('tautan sudah dibuka → reload menghilangkan banner', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified);
      await pumpGate(tester, auth);
      auth.serverEmailVerified = true;
      await tester.tap(find.byKey(const Key('verify-check')));
      await tester.pumpAndSettle();
      expect(find.byType(EmailVerificationBanner), findsNothing);
      expect(find.text('Home A'), findsOneWidget);
      await cleanup(tester, auth);
    });

    testWidgets('kembali ke aplikasi memeriksa status otomatis', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified);
      await pumpGate(tester, auth);
      auth.serverEmailVerified = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(auth.reloads, 1);
      expect(find.byType(EmailVerificationBanner), findsNothing);
      await cleanup(tester, auth);
    });

    testWidgets('offline saat periksa → error, status tidak berubah', (
      tester,
    ) async {
      final auth = SessionAuth(currentUser: unverified)
        ..reloadFailure = FirebaseAuthException(code: 'network-request-failed');
      await pumpGate(tester, auth);
      await tester.tap(find.byKey(const Key('verify-check')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Koneksi gagal'), findsOneWidget);
      expect(find.byType(EmailVerificationBanner), findsOneWidget);
      await cleanup(tester, auth);
    });
  });

  group('SessionController.refreshUser', () {
    test('hasil reload milik sesi lama diabaikan setelah ganti akun', () async {
      final auth = _SlowReloadAuth(unverified);
      final state = AppState.forTesting(
        profiles: MemoryProfiles(),
        transactions: MemoryTransactions(),
      );
      final controller = SessionController(auth, state: state);
      await Future<void>.delayed(Duration.zero);
      expect(controller.user?.uid, 'A');

      final refresh = controller.refreshUser();
      auth.emit(const SessionUser('B', 'b@example.com'));
      await Future<void>.delayed(Duration.zero);
      auth.reloadGate.complete(
        const SessionUser('A', 'a@example.com', emailVerified: true),
      );
      final result = await refresh;

      expect(controller.user?.uid, 'B');
      expect(controller.user?.emailVerified, isFalse);
      expect(result?.uid, 'B');
      controller.dispose();
      await auth.events.close();
    });

    test('perubahan status verifikasi tidak memulai ulang data sesi', () async {
      final auth = SessionAuth(currentUser: unverified);
      final state = AppState.forTesting(
        profiles: MemoryProfiles(),
        transactions: MemoryTransactions(),
      );
      final controller = SessionController(auth, state: state);
      await Future<void>.delayed(Duration.zero);
      await state.retryProfile();
      final revision = state.sessionRevision;

      auth.serverEmailVerified = true;
      await controller.refreshUser();
      await Future<void>.delayed(Duration.zero);

      expect(controller.user?.emailVerified, isTrue);
      expect(state.sessionRevision, revision);
      controller.dispose();
      await auth.events.close();
    });
  });

  testWidgets('pergantian akun mengganti banner dan mereset cooldown', (
    tester,
  ) async {
    final auth = SessionAuth(currentUser: unverified);
    await pumpGate(tester, auth);
    await tester.tap(find.byKey(const Key('verify-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kirim ulang'), findsOneWidget);

    auth.emit(const SessionUser('B', 'b@example.com'));
    await tester.pumpAndSettle();
    expect(find.textContaining('b@example.com'), findsOneWidget);
    expect(find.text('Kirim tautan'), findsOneWidget);
    expect(find.textContaining('a@example.com'), findsNothing);
    await cleanup(tester, auth);
  });
}

class _SlowReloadAuth extends SessionAuth {
  _SlowReloadAuth(SessionUser user) : super(currentUser: user);
  final reloadGate = Completer<SessionUser>();

  @override
  Future<SessionUser?> reloadUser() => reloadGate.future;
}
