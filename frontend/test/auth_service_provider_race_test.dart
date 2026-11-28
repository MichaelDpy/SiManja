import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/screens/account_security_page.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/fake_firebase_auth.dart';
import 'support/session_auth.dart';

/// B2-02: operasi provider async lain tidak melanjutkan ke sesi baru.
void main() {
  late FakeFirebaseAuth auth;
  late FakeGoogleSource google;
  late AuthService service;

  setUp(() {
    auth = FakeFirebaseAuth();
    google = FakeGoogleSource();
    service = AuthService(auth, google: google);
  });

  ReauthGrant grant(String uid, SensitiveOperation op, {DateTime? at}) =>
      ReauthGrant(uid: uid, operation: op, grantedAt: at);

  group('linkGoogle setelah UI Google', () {
    test('sesi sama: Google terhubung ke pemilik grant', () async {
      final a = FakeUser('A', auth, providers: [passwordProviderId]);
      auth.current = a;
      await service.linkGoogle(grant('A', SensitiveOperation.linkProvider));
      expect(auth.mutations, ['A:link:google.com']);
      expect(a.providers, [passwordProviderId, googleProviderId]);
    });

    test(
      'A→B saat memilih akun Google: tidak menghubungkan ke A maupun B',
      () async {
        final a = FakeUser('A', auth, providers: [passwordProviderId]);
        final b = FakeUser('B', auth, providers: [passwordProviderId]);
        auth.current = a;
        google.beforeReturn = () => auth.current = b;
        await expectLater(
          service.linkGoogle(grant('A', SensitiveOperation.linkProvider)),
          throwsA(_code('user-mismatch')),
        );
        expect(auth.mutations, isEmpty);
      },
    );

    test('logout atau masuk ulang saat UI Google: dibatalkan', () async {
      for (final next in <FakeUser? Function()>[
        () => null,
        () => FakeUser('A', auth, providers: [passwordProviderId], signIn: 2),
      ]) {
        auth.mutations.clear();
        auth.current = FakeUser('A', auth, providers: [passwordProviderId]);
        google.beforeReturn = () => auth.current = next();
        await expectLater(
          service.linkGoogle(grant('A', SensitiveOperation.linkProvider)),
          throwsA(_code('user-mismatch')),
        );
        expect(auth.mutations, isEmpty);
      }
    });

    test('grant kedaluwarsa selama UI Google: ditolak sebelum link', () async {
      auth.current = FakeUser('A', auth, providers: [passwordProviderId]);
      final old = grant(
        'A',
        SensitiveOperation.linkProvider,
        at: DateTime.now().subtract(
          ReauthGrant.maxAge - const Duration(milliseconds: 20),
        ),
      );
      google.beforeReturn = () => {};
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await expectLater(
        service.linkGoogle(old),
        throwsA(_code(AuthErrorCodes.reauthMismatch)),
      );
      expect(auth.mutations, isEmpty);
    });

    test('batal memilih akun: tanpa mutasi', () async {
      auth.current = FakeUser('A', auth, providers: [passwordProviderId]);
      final cancelling = AuthService(auth, google: _CancelledGoogle());
      await expectLater(
        cancelling.linkGoogle(grant('A', SensitiveOperation.linkProvider)),
        throwsA(_code(AuthErrorCodes.cancelled)),
      );
      expect(auth.mutations, isEmpty);
    });
  });

  group('reauthenticateWithGoogle', () {
    test('sesi sama: grant terikat UID dan operasi', () async {
      auth.current = FakeUser('G', auth, providers: [googleProviderId]);
      final result = await service.reauthenticateWithGoogle(
        SensitiveOperation.unlinkProvider,
      );
      expect(result.uid, 'G');
      expect(result.operation, SensitiveOperation.unlinkProvider);
      expect(auth.mutations, ['G:reauth:google.com']);
    });

    test(
      'A→B saat UI Google: reauth tidak dijalankan pada objek lama',
      () async {
        auth.current = FakeUser('A', auth, providers: [googleProviderId]);
        google.beforeReturn = () =>
            auth.current = FakeUser('B', auth, providers: [googleProviderId]);
        await expectLater(
          service.reauthenticateWithGoogle(SensitiveOperation.deleteAccount),
          throwsA(_code('user-mismatch')),
        );
        expect(auth.mutations, isEmpty);
      },
    );
  });

  group('reauth password, ganti password, tambah password', () {
    test(
      'akun berganti selama reauth password: tidak menghasilkan grant',
      () async {
        final a = FakeUser('A', auth);
        auth.current = a;
        a.onReauth = () => auth.current = FakeUser('B', auth);
        await expectLater(
          service.reauthenticateWithPassword(
            'Password123!',
            SensitiveOperation.changePassword,
          ),
          throwsA(_code('user-mismatch')),
        );
      },
    );

    test('grant A tidak dapat dipakai pada sesi B', () async {
      auth.current = FakeUser('B', auth);
      await expectLater(
        service.changePassword(
          grant('A', SensitiveOperation.changePassword),
          'PasswordBaru1!',
        ),
        throwsA(_code(AuthErrorCodes.reauthMismatch)),
      );
      await expectLater(
        service.linkPassword(
          grant('A', SensitiveOperation.linkProvider),
          'PasswordBaru1!',
        ),
        throwsA(_code(AuthErrorCodes.reauthMismatch)),
      );
      expect(auth.mutations, isEmpty);
    });
  });

  testWidgets('pesan sukses akun A tidak tampil setelah akun berganti ke B', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _SwitchAfterLink(
      currentUser: const SessionUser(
        'A',
        'a@example.com',
        emailVerified: true,
        providerIds: [passwordProviderId],
      ),
    )..googleSignInAvailable = true;
    await tester.pumpWidget(MaterialApp(home: AccountSecurityPage(auth: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('link-google')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reauth-password')),
      'Password123!',
    );
    await tester.tap(find.byKey(const Key('reauth-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Google terhubung'), findsNothing);
    expect(find.text('a@example.com'), findsNothing);
    expect(find.text('Sesi berakhir. Silakan masuk kembali.'), findsOneWidget);
  });
}

Matcher _code(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);

class _CancelledGoogle implements GoogleIdTokenSource {
  @override
  bool get available => true;
  @override
  Future<String> obtainIdToken() async =>
      throw FirebaseAuthException(code: AuthErrorCodes.cancelled);
}

/// Link berhasil, lalu sesi sudah berganti ke B sebelum hasil ditampilkan.
class _SwitchAfterLink extends SessionAuth {
  _SwitchAfterLink({super.currentUser});

  @override
  Future<void> linkGoogle(ReauthGrant grant) async {
    await super.linkGoogle(grant);
    emit(const SessionUser('B', 'b@example.com', emailVerified: true));
  }
}
