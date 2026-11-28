import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/screens/session_gate.dart';
import 'package:simanja/services/auth_service.dart';
import 'package:simanja/widgets/email_verification_banner.dart';
import 'package:simanja/widgets/session_scope.dart';

import 'support/fake_firebase_auth.dart';
import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// B2-04: status verifikasi mengikuti server Auth dan hasil sesi lama
/// tidak tampil pada akun berikutnya.
void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  group('AuthService produksi', () {
    late FakeFirebaseAuth sdk;
    late AuthService service;

    setUp(() {
      sdk = FakeFirebaseAuth();
      service = AuthService(sdk, google: FakeGoogleSource(available: false));
    });

    test('status awal dan hasil reload berasal dari Firebase Auth', () async {
      final a = FakeUser('A', sdk, providers: [passwordProviderId]);
      sdk.current = a;
      expect(service.currentUser!.emailVerified, isFalse);

      // Tautan dibuka di perangkat lain; lokal masih basi sampai reload.
      a.serverEmailVerified = true;
      expect(service.currentUser!.emailVerified, isFalse);
      final fresh = await service.reloadUser();
      expect(fresh!.uid, 'A');
      expect(fresh.emailVerified, isTrue);
    });

    test(
      'akun berganti selama reload: status akun B tidak dikembalikan',
      () async {
        final a = FakeUser('A', sdk, providers: [passwordProviderId]);
        final b = FakeUser('B', sdk, providers: [passwordProviderId])
          ..serverEmailVerified = true;
        sdk.current = a;
        a.onReload = () => sdk.current = b;
        expect(await service.reloadUser(), isNull);
      },
    );

    test('kirim verifikasi hanya untuk pengguna yang sedang masuk', () async {
      await expectLater(
        service.sendEmailVerification(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            AuthErrorCodes.noCurrentUser,
          ),
        ),
      );
      sdk.current = FakeUser('A', sdk, providers: [passwordProviderId]);
      await service.sendEmailVerification();
      expect(sdk.mutations, ['A:sendVerification']);
    });

    test('status verifikasi tidak bergantung pada profil Firestore', () async {
      final a = FakeUser('A', sdk, providers: [passwordProviderId])
        ..serverEmailVerified = true;
      sdk.current = a;
      await a.reload();
      // SessionUser dibangun dari User Auth; profil tidak punya field ini.
      expect(SessionUser.fromFirebase(a).emailVerified, isTrue);
    });
  });

  group('banner: hasil telat setelah akun berganti', () {
    setUp(() {
      AppState.instance.clearSession();
      AppState.instance.useProfileRepository(MemoryProfiles());
      AppState.instance.useTransactionRepository(MemoryTransactions());
    });

    Future<void> pumpGate(WidgetTester tester, SessionAuth auth) async {
      Widget gate() => SessionGate(
        auth: auth,
        homeBuilder: (context) => Scaffold(
          body: Text('Home ${SessionScope.maybeOf(context)!.user!.uid}'),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await auth.events.close();
        AppState.instance.clearSession();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: gate(),
          routes: {
            '/home': (_) => gate(),
            '/login': (_) => const Text('Login'),
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'kirim A selesai setelah ganti ke B: tanpa pesan/cooldown di B',
      (tester) async {
        final auth = SessionAuth(
          currentUser: const SessionUser('A', 'a@example.com'),
        )..pendingVerification = Completer<void>();
        await pumpGate(tester, auth);
        await tester.tap(find.byKey(const Key('verify-send')));
        await tester.pump();

        auth.emit(const SessionUser('B', 'b@example.com'));
        await tester.pumpAndSettle();
        auth.pendingVerification!.complete();
        await tester.pumpAndSettle();

        expect(
          find.textContaining('b@example.com belum diverifikasi'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('verify-message')), findsNothing);
        expect(find.text('Kirim tautan'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'periksa A selesai setelah ganti ke B: status A tidak dipakai',
      (tester) async {
        final auth = _GatedReloadAuth(const SessionUser('A', 'a@example.com'));
        await pumpGate(tester, auth);
        await tester.tap(find.byKey(const Key('verify-check')));
        await tester.pump();

        auth.emit(const SessionUser('B', 'b@example.com'));
        await tester.pumpAndSettle();
        auth.gate.complete(
          const SessionUser('A', 'a@example.com', emailVerified: true),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EmailVerificationBanner), findsOneWidget);
        expect(
          find.textContaining('b@example.com belum diverifikasi'),
          findsOneWidget,
        );
        expect(find.text('Email sudah terverifikasi.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _GatedReloadAuth extends SessionAuth {
  _GatedReloadAuth(SessionUser user) : super(currentUser: user);
  final gate = Completer<SessionUser>();

  @override
  Future<SessionUser?> reloadUser() => gate.future;
}
