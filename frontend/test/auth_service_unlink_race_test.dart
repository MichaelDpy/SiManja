import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/services/auth_service.dart';

/// B2-01: unlink terikat pada UID dan sesi pemilik grant setelah await.
///
/// Menjalankan [AuthService] produksi dengan seam SDK terkendali: akun dapat
/// berganti tepat ketika `reload()` sedang ditunggu.
void main() {
  late _FakeAuth auth;
  late AuthService service;

  _FakeUser user(String uid, {int signIn = 1, List<String>? providers}) =>
      _FakeUser(
        uid,
        auth,
        providers ?? [passwordProviderId, googleProviderId],
        DateTime.utc(2026, 11, 28, 9, signIn),
      );

  ReauthGrant grantFor(String uid, {DateTime? at}) => ReauthGrant(
    uid: uid,
    operation: SensitiveOperation.unlinkProvider,
    grantedAt: at,
  );

  setUp(() {
    auth = _FakeAuth();
    service = AuthService(auth, google: _GoogleAvailable());
  });

  test(
    'UID sama dan dua metode: unlink dijalankan pada pemilik grant',
    () async {
      final a = user('A');
      auth.current = a;
      await service.unlinkProvider(grantFor('A'), googleProviderId);
      expect(auth.unlinks, ['A:google.com']);
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
    expect(auth.unlinks, isEmpty);
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
    expect(auth.unlinks, isEmpty);
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
    expect(auth.unlinks, isEmpty);
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
      expect(auth.unlinks, isEmpty);
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
    expect(auth.unlinks, isEmpty);
  });

  test('metode terakhir tetap dilindungi anti-lockout', () async {
    final a = user('A', providers: [passwordProviderId]);
    auth.current = a;
    await expectLater(
      service.unlinkProvider(grantFor('A'), passwordProviderId),
      throwsA(_code(AuthErrorCodes.unlinkLockout)),
    );
    expect(auth.unlinks, isEmpty);
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
      expect(auth.unlinks, isEmpty);
    },
  );
}

Matcher _code(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);

class _GoogleAvailable implements GoogleIdTokenSource {
  @override
  bool get available => true;
  @override
  Future<String> obtainIdToken() => throw UnimplementedError();
}

class _FakeAuth extends Fake implements FirebaseAuth {
  User? current;
  final unlinks = <String>[];

  @override
  User? get currentUser => current;
}

class _FakeUser extends Fake implements User {
  _FakeUser(this.uid, this.auth, this.providers, this.signedInAt);

  @override
  final String uid;
  final _FakeAuth auth;
  List<String> providers;
  final DateTime signedInAt;
  int reloads = 0;
  void Function()? onReload;
  Future<void> Function()? onReloadAsync;

  @override
  String? get email => '$uid@example.com';

  @override
  List<UserInfo> get providerData => [
    for (final id in providers) _FakeInfo(id),
  ];

  @override
  UserMetadata get metadata => _FakeMetadata(signedInAt);

  @override
  Future<void> reload() async {
    reloads++;
    await onReloadAsync?.call();
    onReload?.call();
    onReload = null;
  }

  @override
  Future<User> unlink(String providerId) async {
    auth.unlinks.add('$uid:$providerId');
    providers = [
      for (final id in providers)
        if (id != providerId) id,
    ];
    return this;
  }
}

class _FakeInfo extends Fake implements UserInfo {
  _FakeInfo(this.providerId);
  @override
  final String providerId;
}

class _FakeMetadata extends Fake implements UserMetadata {
  _FakeMetadata(this.lastSignInTime);
  @override
  final DateTime? lastSignInTime;
}
