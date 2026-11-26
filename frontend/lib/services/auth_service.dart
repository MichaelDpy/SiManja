import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/firebase_bootstrap.dart';

/// Identitas sesi dari Firebase Auth. Bukan profil Firestore.
class SessionUser {
  final String uid;
  final String email;

  /// Status verifikasi email menurut server Auth (diperbarui lewat reload).
  final bool emailVerified;

  /// ID provider masuk, misalnya `password` atau `google.com`.
  final List<String> providerIds;

  /// Waktu masuk terakhir menurut metadata Auth, bila tersedia.
  final DateTime? lastSignInTime;

  const SessionUser(
    this.uid,
    this.email, {
    this.emailVerified = false,
    this.providerIds = const ['password'],
    this.lastSignInTime,
  });

  bool get hasPasswordProvider => providerIds.contains('password');

  factory SessionUser.fromFirebase(User user) => SessionUser(
    user.uid,
    user.email ?? '',
    emailVerified: user.emailVerified,
    providerIds: [
      for (final info in user.providerData)
        if (info.providerId.isNotEmpty) info.providerId,
    ],
    lastSignInTime: user.metadata.lastSignInTime,
  );

  @override
  bool operator ==(Object other) =>
      other is SessionUser &&
      other.uid == uid &&
      other.email == email &&
      other.emailVerified == emailVerified &&
      _sameList(other.providerIds, providerIds);

  @override
  int get hashCode =>
      Object.hash(uid, email, emailVerified, providerIds.length);

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Operasi sensitif yang memerlukan autentikasi ulang (recent login).
enum SensitiveOperation {
  changePassword('mengganti password'),
  deleteAccount('menghapus akun'),
  linkProvider('menghubungkan metode masuk'),
  unlinkProvider('melepas metode masuk');

  const SensitiveOperation(this.label);
  final String label;
}

/// Bukti autentikasi ulang yang terikat pada satu UID dan satu operasi.
///
/// Hanya berlaku singkat ([maxAge]); operasi sensitif menolak bukti milik UID
/// lain, operasi lain, atau yang sudah kedaluwarsa.
class ReauthGrant {
  ReauthGrant({required this.uid, required this.operation, DateTime? grantedAt})
    : grantedAt = grantedAt ?? DateTime.now();

  static const maxAge = Duration(minutes: 5);

  final String uid;
  final SensitiveOperation operation;
  final DateTime grantedAt;

  bool allows(String currentUid, SensitiveOperation op, {DateTime? now}) =>
      uid == currentUid &&
      operation == op &&
      (now ?? DateTime.now()).difference(grantedAt) <= maxAge;
}

/// Hasil pemeriksaan password terhadap kebijakan project.
class PasswordCheck {
  const PasswordCheck(this.unmet, {required this.fromServerPolicy});

  /// Persyaratan yang belum terpenuhi, dalam Bahasa Indonesia.
  final List<String> unmet;

  /// true bila kebijakan diambil dari project Firebase; false bila memakai
  /// batas minimum Firebase karena kebijakan tidak dapat diambil.
  final bool fromServerPolicy;

  bool get isValid => unmet.isEmpty;
}

/// Batas bawah Firebase Auth untuk akun email/password. Kebijakan project
/// boleh lebih ketat; server tetap penentu akhir.
const firebaseMinPasswordLength = 6;
const firebaseMaxPasswordLength = 4096;

abstract interface class AuthGateway {
  Stream<SessionUser?> get authStateChanges;
  SessionUser? get currentUser;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();

  /// Memeriksa password baru terhadap kebijakan project bila tersedia.
  Future<PasswordCheck> checkPassword(String password);

  /// Mengirim email verifikasi ke pengguna yang sedang masuk.
  Future<void> sendEmailVerification();

  /// Memuat ulang status pengguna dari server Auth.
  Future<SessionUser?> reloadUser();

  /// Autentikasi ulang dengan password untuk satu operasi sensitif.
  Future<ReauthGrant> reauthenticateWithPassword(
    String password,
    SensitiveOperation operation,
  );

  /// Mengganti password; wajib membawa [ReauthGrant] yang masih berlaku.
  Future<void> changePassword(ReauthGrant grant, String newPassword);

  // ── Google & pengelolaan metode masuk (B06–B08) ─────────────────────────

  /// true bila login Google dapat dipakai di perangkat/konfigurasi ini.
  bool get googleSignInAvailable;

  /// Masuk dengan Google. Batal → [AuthErrorCodes.cancelled]. Email yang
  /// sudah terdaftar dengan metode lain tidak digabung otomatis.
  Future<void> signInWithGoogle();

  /// Autentikasi ulang lewat Google untuk akun yang terhubung Google.
  Future<ReauthGrant> reauthenticateWithGoogle(SensitiveOperation operation);

  /// Menghubungkan Google ke UID yang sedang masuk (grant [linkProvider]).
  Future<void> linkGoogle(ReauthGrant grant);

  /// Menambahkan password ke akun tanpa password (grant [linkProvider]).
  Future<void> linkPassword(ReauthGrant grant, String newPassword);

  /// Melepas satu metode masuk (grant [unlinkProvider]); ditolak bila akan
  /// mengunci akun (lihat [unlinkBlockReason]).
  Future<void> unlinkProvider(ReauthGrant grant, String providerId);
}

const passwordProviderId = 'password';
const googleProviderId = 'google.com';

/// Alasan melepas [target] harus ditolak, atau null bila aman.
///
/// Aman hanya bila tersisa minimal satu metode yang benar-benar dapat dipakai
/// di perangkat ini: password selalu dapat dipakai; Google hanya bila
/// [googleAvailable]; provider lain (mis. Apple) belum didukung aplikasi.
String? unlinkBlockReason(
  List<String> providers,
  String target, {
  required bool googleAvailable,
}) {
  if (!providers.contains(target)) return 'Metode ini tidak terhubung.';
  final remaining = providers.where((id) => id != target).toList();
  if (remaining.isEmpty) {
    return 'Tidak bisa melepas satu-satunya metode masuk. Tambahkan metode '
        'lain terlebih dahulu.';
  }
  final usable = remaining.any(
    (id) =>
        id == passwordProviderId || (id == googleProviderId && googleAvailable),
  );
  if (!usable) {
    return 'Metode yang tersisa belum bisa dipakai untuk masuk di perangkat '
        'ini. Tambahkan password terlebih dahulu.';
  }
  return null;
}

/// Sumber ID token Google native (Android/iOS), dipisah agar dapat diuji.
abstract interface class GoogleIdTokenSource {
  bool get available;

  /// Menjalankan UI Google dan mengembalikan ID token.
  /// Batal → FirebaseAuthException(code: [AuthErrorCodes.cancelled]).
  Future<String> obtainIdToken();
}

/// Google Sign-In resmi (`google_sign_in`) dengan Web client ID project.
class NativeGoogleIdTokenSource implements GoogleIdTokenSource {
  NativeGoogleIdTokenSource(this.serverClientId);
  final String serverClientId;
  Future<void>? _init;

  @override
  bool get available =>
      !kIsWeb &&
      serverClientId.isNotEmpty &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String> obtainIdToken() async {
    if (!available) {
      throw FirebaseAuthException(code: AuthErrorCodes.googleUnavailable);
    }
    final signIn = GoogleSignIn.instance;
    await (_init ??= signIn.initialize(serverClientId: serverClientId));
    try {
      // Selalu tampilkan pemilih akun: hindari memakai akun Google terakhir
      // secara diam-diam saat berganti akun SIMANJA.
      await signIn.signOut();
      final account = await signIn.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw FirebaseAuthException(code: AuthErrorCodes.googleUnavailable);
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        throw FirebaseAuthException(code: AuthErrorCodes.cancelled);
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw FirebaseAuthException(code: AuthErrorCodes.googleUnavailable);
      }
      throw FirebaseAuthException(code: 'network-request-failed');
    }
  }
}

/// Kode error untuk kondisi yang dibuat aplikasi (bukan dari SDK).
abstract final class AuthErrorCodes {
  static const noCurrentUser = 'no-current-user';
  static const reauthProviderUnsupported = 'reauth-provider-unsupported';
  static const reauthMismatch = 'reauth-grant-invalid';
  static const cancelled = 'cancelled';
  static const googleUnavailable = 'google-unavailable';
  static const unlinkLockout = 'unlink-would-lockout';
}

class AuthService implements AuthGateway {
  AuthService(this._auth, {GoogleIdTokenSource? google})
    : _google =
          google ??
          NativeGoogleIdTokenSource(
            FirebaseBootstrap.config?.googleServerClientId ?? '',
          );
  final FirebaseAuth _auth;
  final GoogleIdTokenSource _google;
  static AuthService get instance => AuthService(FirebaseBootstrap.auth);

  /// Ketersediaan Google untuk konfigurasi build ini tanpa menyentuh
  /// instance Firebase (aman dipanggil saat build sebelum/ tanpa bootstrap).
  static bool get defaultGoogleAvailable =>
      kIsWeb ||
      NativeGoogleIdTokenSource(
        FirebaseBootstrap.config?.googleServerClientId ?? '',
      ).available;

  /// userChanges juga memancarkan perubahan profil/token (mis. setelah
  /// reload), sehingga status verifikasi email ikut terbarui.
  @override
  Stream<SessionUser?> get authStateChanges => _auth.userChanges().map(
    (user) => user == null ? null : SessionUser.fromFirebase(user),
  );

  @override
  SessionUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : SessionUser.fromFirebase(user);
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Permintaan pemulihan tidak membedakan email terdaftar atau tidak.
  /// `user-not-found` (bila perlindungan enumerasi project nonaktif) ditelan
  /// supaya UI tidak membocorkan keberadaan akun.
  @override
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') return;
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<PasswordCheck> checkPassword(String password) async {
    final local = localPasswordIssues(password);
    // Emulator memakai API key demo: kebijakan project tidak dapat diambil.
    if (FirebaseBootstrap.useEmulators || password.isEmpty) {
      return PasswordCheck(local, fromServerPolicy: false);
    }
    try {
      final status = await _auth.validatePassword(_auth, password);
      final policy = status.passwordPolicy;
      return PasswordCheck([
        if (!status.meetsMinPasswordLength)
          'Minimal ${policy.minPasswordLength} karakter',
        if (status.meetsMaxPasswordLength == false)
          'Maksimal ${policy.maxPasswordLength} karakter',
        if (status.meetsLowercaseRequirement == false)
          'Memuat huruf kecil (a–z)',
        if (status.meetsUppercaseRequirement == false)
          'Memuat huruf besar (A–Z)',
        if (status.meetsDigitsRequirement == false) 'Memuat angka (0–9)',
        if (status.meetsSymbolsRequirement == false)
          'Memuat simbol, misalnya ! @ # \$',
      ], fromServerPolicy: true);
    } catch (_) {
      // Offline/kebijakan tidak terjangkau: pakai batas minimum Firebase,
      // server tetap menolak password yang tidak memenuhi kebijakan.
      return PasswordCheck(local, fromServerPolicy: false);
    }
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: AuthErrorCodes.noCurrentUser);
    }
    return user;
  }

  @override
  Future<void> sendEmailVerification() =>
      _requireUser().sendEmailVerification();

  @override
  Future<SessionUser?> reloadUser() async {
    final user = _requireUser();
    await user.reload();
    final fresh = _auth.currentUser;
    if (fresh == null || fresh.uid != user.uid) return null;
    return SessionUser.fromFirebase(fresh);
  }

  @override
  Future<ReauthGrant> reauthenticateWithPassword(
    String password,
    SensitiveOperation operation,
  ) async {
    final user = _requireUser();
    final email = user.email;
    final hasPassword = user.providerData.any(
      (info) => info.providerId == EmailAuthProvider.PROVIDER_ID,
    );
    if (!hasPassword || email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: AuthErrorCodes.reauthProviderUnsupported,
      );
    }
    final result = await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    final uid = result.user?.uid ?? user.uid;
    if (uid != user.uid || _auth.currentUser?.uid != user.uid) {
      throw FirebaseAuthException(code: 'user-mismatch');
    }
    return ReauthGrant(uid: uid, operation: operation);
  }

  @override
  Future<void> changePassword(ReauthGrant grant, String newPassword) async {
    final user = _requireUser();
    if (!grant.allows(user.uid, SensitiveOperation.changePassword)) {
      throw FirebaseAuthException(code: AuthErrorCodes.reauthMismatch);
    }
    await user.updatePassword(newPassword);
  }

  // ── Google & metode masuk ───────────────────────────────────────────────

  /// Web memakai popup Firebase (juga didukung Auth Emulator); Android
  /// memakai google_sign_in dan membutuhkan GOOGLE_SERVER_CLIENT_ID.
  @override
  bool get googleSignInAvailable => kIsWeb || _google.available;

  GoogleAuthProvider get _webProvider =>
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});

  Future<AuthCredential> _nativeGoogleCredential() async =>
      GoogleAuthProvider.credential(idToken: await _google.obtainIdToken());

  /// Popup ditutup pengguna di Web diperlakukan sebagai batal.
  Future<T> _guardCancel<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'popup-closed-by-user' ||
          error.code == 'cancelled-popup-request' ||
          error.code == 'web-context-canceled') {
        throw FirebaseAuthException(code: AuthErrorCodes.cancelled);
      }
      rethrow;
    }
  }

  void _requireGoogle() {
    if (!googleSignInAvailable) {
      throw FirebaseAuthException(code: AuthErrorCodes.googleUnavailable);
    }
  }

  @override
  Future<void> signInWithGoogle() => _guardCancel(() async {
    _requireGoogle();
    if (kIsWeb) {
      await _auth.signInWithPopup(_webProvider);
    } else {
      await _auth.signInWithCredential(await _nativeGoogleCredential());
    }
  });

  @override
  Future<ReauthGrant> reauthenticateWithGoogle(SensitiveOperation operation) =>
      _guardCancel(() async {
        _requireGoogle();
        final user = _requireUser();
        if (!user.providerData.any((i) => i.providerId == googleProviderId)) {
          throw FirebaseAuthException(
            code: AuthErrorCodes.reauthProviderUnsupported,
          );
        }
        final result = kIsWeb
            ? await user.reauthenticateWithPopup(_webProvider)
            : await user.reauthenticateWithCredential(
                await _nativeGoogleCredential(),
              );
        final uid = result.user?.uid ?? user.uid;
        if (uid != user.uid || _auth.currentUser?.uid != user.uid) {
          throw FirebaseAuthException(code: 'user-mismatch');
        }
        return ReauthGrant(uid: uid, operation: operation);
      });

  User _requireGrant(ReauthGrant grant, SensitiveOperation operation) {
    final user = _requireUser();
    if (!grant.allows(user.uid, operation)) {
      throw FirebaseAuthException(code: AuthErrorCodes.reauthMismatch);
    }
    return user;
  }

  /// Menghubungkan ke UID yang sama; tidak pernah menggabungkan dua UID.
  /// `credential-already-in-use` diteruskan agar UI menjelaskannya.
  @override
  Future<void> linkGoogle(ReauthGrant grant) => _guardCancel(() async {
    _requireGoogle();
    final user = _requireGrant(grant, SensitiveOperation.linkProvider);
    if (kIsWeb) {
      await user.linkWithPopup(_webProvider);
    } else {
      await user.linkWithCredential(await _nativeGoogleCredential());
    }
    await user.reload();
  });

  @override
  Future<void> linkPassword(ReauthGrant grant, String newPassword) async {
    final user = _requireGrant(grant, SensitiveOperation.linkProvider);
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(code: 'missing-email');
    }
    // linkWithCredential(EmailAuthProvider) dengan email akun Google ditolak
    // `email-already-in-use` (terbukti di Auth Emulator). updatePassword pada
    // akun tanpa password menambahkan provider `password` ke UID yang sama.
    await user.updatePassword(newPassword);
    await user.reload();
  }

  @override
  Future<void> unlinkProvider(ReauthGrant grant, String providerId) async {
    final user = _requireGrant(grant, SensitiveOperation.unlinkProvider);
    await user.reload();
    final fresh = _auth.currentUser ?? user;
    final reason = unlinkBlockReason(
      [for (final info in fresh.providerData) info.providerId],
      providerId,
      googleAvailable: googleSignInAvailable,
    );
    if (reason != null) {
      throw FirebaseAuthException(
        code: AuthErrorCodes.unlinkLockout,
        message: reason,
      );
    }
    await fresh.unlink(providerId);
    await fresh.reload();
  }
}

/// Pemeriksaan lokal: hanya batas Firebase, tidak lebih lemah dan tidak
/// menebak aturan tambahan project.
List<String> localPasswordIssues(String password) => [
  if (password.length < firebaseMinPasswordLength)
    'Minimal $firebaseMinPasswordLength karakter',
  if (password.length > firebaseMaxPasswordLength)
    'Maksimal $firebaseMaxPasswordLength karakter',
];

/// Validator form untuk password baru (pendaftaran / ganti password).
String? validateNewPassword(String? input) {
  final password = input ?? '';
  if (password.isEmpty) return 'Password wajib diisi';
  final issues = localPasswordIssues(password);
  return issues.isEmpty ? null : 'Password: ${issues.join(', ')}';
}

/// Pesan Indonesia untuk error Auth. Tidak pernah menampilkan pesan SDK
/// mentah karena bisa memuat detail kredensial.
String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    // Satu-satunya pesan yang diteruskan: alasan buatan aplikasi sendiri.
    if (error.code == AuthErrorCodes.unlinkLockout) {
      return error.message ?? 'Metode masuk tidak dapat dilepas.';
    }
    return switch (error.code) {
      AuthErrorCodes.cancelled => 'Dibatalkan.',
      AuthErrorCodes.googleUnavailable =>
        'Login Google belum dikonfigurasi untuk aplikasi ini.',
      'account-exists-with-different-credential' =>
        'Email ini sudah terdaftar dengan metode lain. Masuk dengan metode '
            'tersebut, lalu hubungkan Google dari Keamanan Akun.',
      'credential-already-in-use' =>
        'Akun Google ini sudah dipakai akun SIMANJA lain. Akun tidak digabung '
            'otomatis.',
      'provider-already-linked' => 'Metode masuk ini sudah terhubung.',
      'no-such-provider' => 'Metode masuk ini sudah tidak terhubung.',
      'popup-blocked' =>
        'Jendela login diblokir browser. Izinkan pop-up lalu coba lagi.',
      'invalid-email' || 'missing-email' => 'Format email tidak valid.',
      'invalid-credential' ||
      'invalid-login-credentials' ||
      'wrong-password' ||
      'user-not-found' => 'Email atau password salah.',
      'missing-password' || 'invalid-password' => 'Password wajib diisi.',
      'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
      'weak-password' || 'password-does-not-meet-requirements' =>
        passwordPolicyMessage(error.message),
      'network-request-failed' =>
        'Koneksi gagal. Periksa jaringan atau emulator, lalu coba lagi.',
      'too-many-requests' || 'quota-exceeded' =>
        'Terlalu banyak percobaan. Tunggu beberapa saat lalu coba lagi.',
      'user-disabled' =>
        'Akun dinonaktifkan. Hubungi pengelola aplikasi untuk bantuan.',
      'operation-not-allowed' =>
        'Metode masuk ini belum diaktifkan pada project Firebase.',
      'requires-recent-login' =>
        'Demi keamanan, masukkan ulang password Anda untuk melanjutkan.',
      'user-token-expired' ||
      'invalid-user-token' ||
      'user-mismatch' ||
      AuthErrorCodes.noCurrentUser => 'Sesi berakhir. Silakan masuk kembali.',
      AuthErrorCodes.reauthProviderUnsupported =>
        'Akun ini tidak memakai password. Verifikasi ulang lewat metode '
            'masuk akun tersebut.',
      AuthErrorCodes.reauthMismatch =>
        'Verifikasi ulang sudah tidak berlaku. Masukkan password lagi.',
      'expired-action-code' => 'Tautan sudah kedaluwarsa. Minta tautan baru.',
      'invalid-action-code' =>
        'Tautan tidak valid atau sudah dipakai. Minta tautan baru.',
      _ => 'Permintaan akun gagal. Silakan coba lagi.',
    };
  }
  return 'Layanan akun belum tersedia. Periksa konfigurasi Firebase.';
}

/// Menerjemahkan daftar persyaratan dari `password-does-not-meet-requirements`
/// (format server: "Missing password requirements: [..., ...]").
String passwordPolicyMessage(String? serverMessage) {
  const fallback = 'Password belum memenuhi kebijakan keamanan akun.';
  final text = serverMessage ?? '';
  final match = RegExp(r'\[(.*)\]').firstMatch(text);
  if (match == null) return fallback;
  final parts = <String>[];
  for (final raw in match.group(1)!.split(',')) {
    final item = raw.trim().toLowerCase();
    final length = RegExp(r'(\d+)').firstMatch(item);
    // "non-alphanumeric" diperiksa sebelum "numeric" karena memuat kata itu.
    if (item.contains('non-alphanumeric') || item.contains('symbol')) {
      parts.add('simbol');
    } else if (item.contains('lower')) {
      parts.add('huruf kecil');
    } else if (item.contains('upper')) {
      parts.add('huruf besar');
    } else if (item.contains('numeric') || item.contains('digit')) {
      parts.add('angka');
    } else if (length != null &&
        (item.contains('length') || item.contains('character'))) {
      parts.add(
        item.contains('max') || item.contains('at most')
            ? 'maksimal ${length.group(1)} karakter'
            : 'minimal ${length.group(1)} karakter',
      );
    }
  }
  if (parts.isEmpty) return fallback;
  return 'Password belum memenuhi kebijakan: ${parts.join(', ')}.';
}

String? validateEmail(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return 'Email wajib diisi';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return 'Format email tidak valid';
  }
  return null;
}
