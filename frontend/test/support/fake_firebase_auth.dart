import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/services/auth_service.dart';

/// Seam SDK terkendali untuk menjalankan [AuthService] produksi di tes.
/// Akun dapat diganti tepat ketika operasi async sedang ditunggu.
class FakeFirebaseAuth extends Fake implements FirebaseAuth {
  User? current;

  /// Log mutasi berformat `uid:aksi:detail`.
  final mutations = <String>[];

  @override
  User? get currentUser => current;

  /// Email yang dianggap terdaftar untuk sendPasswordResetEmail.
  final registered = <String>{};
  Object? resetFailure;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    mutations.add('reset:$email');
    if (resetFailure != null) throw resetFailure!;
    if (!registered.contains(email)) {
      // Perilaku project tanpa perlindungan enumerasi (terbukti di emulator).
      throw FirebaseAuthException(code: 'user-not-found');
    }
  }
}

class FakeUser extends Fake implements User {
  FakeUser(this.uid, this.auth, {List<String>? providers, int signIn = 1})
    : providers = providers ?? [passwordProviderId, googleProviderId],
      signedInAt = DateTime.utc(2026, 11, 28, 9, signIn);

  @override
  final String uid;
  final FakeFirebaseAuth auth;
  List<String> providers;
  final DateTime signedInAt;
  int reloads = 0;

  /// Dipanggil saat reload (setelah [onReloadAsync]), sekali.
  void Function()? onReload;
  Future<void> Function()? onReloadAsync;

  /// Dipanggil sebelum reauthenticateWithCredential selesai, sekali.
  void Function()? onReauth;

  @override
  String? get email => '$uid@example.com';

  /// Status verifikasi menurut "server"; terlihat setelah reload.
  bool serverEmailVerified = false;
  bool _emailVerified = false;

  @override
  bool get emailVerified => _emailVerified;

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    auth.mutations.add('$uid:sendVerification');
  }

  @override
  List<UserInfo> get providerData => [
    for (final id in providers) _FakeInfo(id),
  ];

  @override
  UserMetadata get metadata => _FakeMetadata(signedInAt);

  @override
  Future<void> reload() async {
    reloads++;
    _emailVerified = serverEmailVerified;
    await onReloadAsync?.call();
    onReload?.call();
    onReload = null;
  }

  @override
  Future<User> unlink(String providerId) async {
    auth.mutations.add('$uid:unlink:$providerId');
    providers = [
      for (final id in providers)
        if (id != providerId) id,
    ];
    return this;
  }

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    auth.mutations.add('$uid:link:${credential.providerId}');
    providers = [...providers, credential.providerId];
    return FakeUserCredential(this);
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    onReauth?.call();
    onReauth = null;
    auth.mutations.add('$uid:reauth:${credential.providerId}');
    return FakeUserCredential(this);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    auth.mutations.add('$uid:updatePassword');
  }
}

class FakeUserCredential extends Fake implements UserCredential {
  FakeUserCredential(this.user);
  @override
  final User? user;
}

/// Sumber ID token Google yang dapat ditunda dan menjalankan efek samping
/// (mis. mengganti akun) sebelum token dikembalikan.
class FakeGoogleSource implements GoogleIdTokenSource {
  FakeGoogleSource({this.available = true});
  @override
  bool available;
  void Function()? beforeReturn;
  int calls = 0;

  @override
  Future<String> obtainIdToken() async {
    calls++;
    await Future<void>.delayed(Duration.zero);
    beforeReturn?.call();
    beforeReturn = null;
    return 'id-token-tes';
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
