import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:simanja/services/auth_service.dart';

class SessionAuth implements AuthGateway {
  SessionAuth({this.currentUser, this.emitInitial = true});
  @override
  SessionUser? currentUser;
  final bool emitInitial;
  final events = StreamController<SessionUser?>.broadcast(sync: true);
  Completer<void>? pendingSignOut;
  Object? signOutFailure;
  int signOutCalls = 0;
  bool emitSignOutEvent = true;

  // ── Verifikasi email (B04) ──────────────────────────────────────────────
  int verificationsSent = 0;
  Object? verificationFailure;
  Completer<void>? pendingVerification;

  /// Status yang dikembalikan server pada reload berikutnya.
  bool serverEmailVerified = false;
  Object? reloadFailure;
  int reloads = 0;

  // ── Autentikasi ulang (B05) ─────────────────────────────────────────────
  String validPassword = 'Password123!';
  Object? reauthFailure;
  Completer<void>? pendingReauth;
  final reauthCalls = <SensitiveOperation>[];
  final passwordChanges = <String>[];
  Object? changePasswordFailure;

  @override
  Stream<SessionUser?> get authStateChanges => Stream.multi((sink) {
    if (emitInitial) sink.add(currentUser);
    final subscription = events.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
  });

  void emit(SessionUser? user) {
    currentUser = user;
    events.add(user);
  }

  @override
  Future<void> signIn(String email, String password) async =>
      emit(SessionUser(email.trim(), email.trim()));
  @override
  Future<void> signUp(String email, String password) => signIn(email, password);
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> signOut() async {
    signOutCalls++;
    await pendingSignOut?.future;
    if (signOutFailure != null) throw signOutFailure!;
    if (emitSignOutEvent) emit(null);
  }

  @override
  Future<PasswordCheck> checkPassword(String password) async =>
      PasswordCheck(localPasswordIssues(password), fromServerPolicy: false);

  @override
  Future<void> sendEmailVerification() async {
    if (currentUser == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    await pendingVerification?.future;
    if (verificationFailure != null) throw verificationFailure!;
    verificationsSent++;
  }

  @override
  Future<SessionUser?> reloadUser() async {
    reloads++;
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    if (reloadFailure != null) throw reloadFailure!;
    final fresh = SessionUser(
      user.uid,
      user.email,
      emailVerified: serverEmailVerified,
      providerIds: user.providerIds,
    );
    emit(fresh);
    return fresh;
  }

  @override
  Future<ReauthGrant> reauthenticateWithPassword(
    String password,
    SensitiveOperation operation,
  ) async {
    reauthCalls.add(operation);
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    if (!user.hasPasswordProvider) {
      throw FirebaseAuthException(
        code: AuthErrorCodes.reauthProviderUnsupported,
      );
    }
    await pendingReauth?.future;
    if (reauthFailure != null) throw reauthFailure!;
    if (password != validPassword) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    return ReauthGrant(uid: user.uid, operation: operation);
  }

  @override
  Future<void> changePassword(ReauthGrant grant, String newPassword) async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    if (!grant.allows(user.uid, SensitiveOperation.changePassword)) {
      throw FirebaseAuthException(code: AuthErrorCodes.reauthMismatch);
    }
    if (changePasswordFailure != null) throw changePasswordFailure!;
    passwordChanges.add(newPassword);
    validPassword = newPassword;
  }

  // ── Google & metode masuk (B06–B08) ─────────────────────────────────────
  @override
  bool googleSignInAvailable = false;

  /// Hasil UI Google berikutnya: null → batal.
  String? googleEmail = 'g@gmail.com';
  Object? googleFailure;
  Completer<void>? pendingGoogle;
  final googleCalls = <String>[];
  final unlinked = <String>[];

  Future<void> _google(String action) async {
    googleCalls.add(action);
    if (!googleSignInAvailable) {
      throw FirebaseAuthException(code: AuthErrorCodes.googleUnavailable);
    }
    await pendingGoogle?.future;
    if (googleFailure != null) throw googleFailure!;
    if (googleEmail == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.cancelled);
    }
  }

  void _setProviders(List<String> providers) {
    final user = currentUser!;
    emit(
      SessionUser(
        user.uid,
        user.email,
        emailVerified: user.emailVerified,
        providerIds: providers,
      ),
    );
  }

  @override
  Future<void> signInWithGoogle() async {
    await _google('signIn');
    emit(
      SessionUser(
        'google-$googleEmail',
        googleEmail!,
        emailVerified: true,
        providerIds: const [googleProviderId],
      ),
    );
  }

  @override
  Future<ReauthGrant> reauthenticateWithGoogle(
    SensitiveOperation operation,
  ) async {
    reauthCalls.add(operation);
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    if (!user.providerIds.contains(googleProviderId)) {
      throw FirebaseAuthException(
        code: AuthErrorCodes.reauthProviderUnsupported,
      );
    }
    await _google('reauth');
    return ReauthGrant(uid: user.uid, operation: operation);
  }

  ReauthGrant _check(ReauthGrant grant, SensitiveOperation op) {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    if (!grant.allows(user.uid, op)) {
      throw FirebaseAuthException(code: AuthErrorCodes.reauthMismatch);
    }
    return grant;
  }

  @override
  Future<void> linkGoogle(ReauthGrant grant) async {
    _check(grant, SensitiveOperation.linkProvider);
    await _google('link');
    _setProviders([...currentUser!.providerIds, googleProviderId]);
  }

  @override
  Future<void> linkPassword(ReauthGrant grant, String newPassword) async {
    _check(grant, SensitiveOperation.linkProvider);
    validPassword = newPassword;
    _setProviders([...currentUser!.providerIds, passwordProviderId]);
  }

  @override
  Future<void> unlinkProvider(ReauthGrant grant, String providerId) async {
    _check(grant, SensitiveOperation.unlinkProvider);
    final reason = unlinkBlockReason(
      currentUser!.providerIds,
      providerId,
      googleAvailable: googleSignInAvailable,
    );
    if (reason != null) {
      throw FirebaseAuthException(
        code: AuthErrorCodes.unlinkLockout,
        message: reason,
      );
    }
    unlinked.add(providerId);
    _setProviders([
      for (final id in currentUser!.providerIds)
        if (id != providerId) id,
    ]);
  }
}
