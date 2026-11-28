import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/fake_firebase_auth.dart';

/// B2-01: unlink terikat pada UID dan sesi pemilik grant setelah await.
///
/// Menjalankan [AuthService] produksi dengan seam SDK terkendali: akun dapat
/// berganti tepat ketika `reload()` sedang ditunggu.
void main() {
  late FakeFirebaseAuth auth;
  late AuthService service;

  FakeUser user(String uid, {int signIn = 1, List<String>? providers}) =>
      FakeUser(uid, auth, providers: providers, signIn: signIn);

  ReauthGrant grantFor(String uid, {DateTime? at}) => ReauthGrant(
    uid: uid,
    operation: SensitiveOperation.unlinkProvider,
    grantedAt: at,
  );

  List<String> unlinks() =>
      auth.mutations.where((m) => m.contains(':unlink:')).toList();

  setUp(() {
    auth = FakeFirebaseAuth();
    service = AuthService(auth, google: FakeGoogleSource());
  });

  test(
    'UID sama dan dua metode: unlink dijalankan pada pemilik grant',
    () async {
      final a = user('A');
      auth.current = a;
      await service.unlinkProvider(grantFor('A'), googleProviderId);
      expect(unlinks(), ['A:unlink:google.com']);
      expect(a.providers, [passwordProviderId]);
    },
  );

  test('A→B selama reload: tidak ada unlink pada akun B', () async {
    final a = user('A');
    final b = user('B');
    auth.current = a;
    a.onReload = () => auth.current = b;

    await expectLater(
      service.unlinkProvider(grantFor('A'), googleProviderId),
      throwsA(_code('user-mismatch')),
    );
    expect(unlinks(), isEmpty);
    expect(b.providers, [passwordProviderId, googleProviderId]);
  });

  test('logout selama reload: tidak memakai objek akun lama', () async {
    final a = user('A');
    auth.current = a;
    a.onReload = () => auth.current = null;

    await expectLater(
      service.unlinkProvider(grantFor('A'), googleProviderId),
      throwsA(_code('user-mismatch')),
    );
    expect(unlinks(), isEmpty);
  });

  test('A→B→A (masuk ulang) selama reload: dianggap sesi berbeda', () async {
    final a = user('A', signIn: 1);
    final aAgain = user('A', signIn: 2);
    auth.current = a;
    a.onReload = () => auth.current = aAgain;

    await expectLater(
      service.unlinkProvider(grantFor('A'), googleProviderId),
      throwsA(_code('user-mismatch')),
    );
    expect(unlinks(), isEmpty);
  });

  test(
    'grant kedaluwarsa saat reload selesai: ditolak sebelum mutasi',
    () async {
      final a = user('A');
      auth.current = a;
      final grant = grantFor(
        'A',
        at: DateTime.now().subtract(
          ReauthGrant.maxAge - const Duration(milliseconds: 50),
        ),
      );
      a.onReloadAsync = () =>
          Future<void>.delayed(const Duration(milliseconds: 120));

      await expectLater(
        service.unlinkProvider(grant, googleProviderId),
        throwsA(_code(AuthErrorCodes.reauthMismatch)),
      );
      expect(unlinks(), isEmpty);
    },
  );

  test('grant milik UID lain atau operasi lain ditolak tanpa reload', () async {
    final a = user('A');
    auth.current = a;
    await expectLater(
      service.unlinkProvider(grantFor('B'), googleProviderId),
      throwsA(_code(AuthErrorCodes.reauthMismatch)),
    );
    await expectLater(
      service.unlinkProvider(
        ReauthGrant(uid: 'A', operation: SensitiveOperation.linkProvider),
        googleProviderId,
      ),
      throwsA(_code(AuthErrorCodes.reauthMismatch)),
    );
    expect(a.reloads, 0);
    expect(unlinks(), isEmpty);
  });

  test('metode terakhir tetap dilindungi anti-lockout', () async {
    final a = user('A', providers: [passwordProviderId]);
    auth.current = a;
    await expectLater(
      service.unlinkProvider(grantFor('A'), passwordProviderId),
      throwsA(_code(AuthErrorCodes.unlinkLockout)),
    );
    expect(unlinks(), isEmpty);
  });

  test(
    'anti-lockout memakai provider terbaru dari server setelah reload',
    () async {
      final a = user('A');
      auth.current = a;
      // Perangkat lain sudah melepas Google; daftar lokal masih basi.
      a.onReload = () => a.providers = [passwordProviderId];
      await expectLater(
        service.unlinkProvider(grantFor('A'), passwordProviderId),
        throwsA(_code(AuthErrorCodes.unlinkLockout)),
      );
      expect(unlinks(), isEmpty);
    },
  );
}

Matcher _code(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);
