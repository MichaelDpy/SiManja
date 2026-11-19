import 'package:firebase_auth/firebase_auth.dart';

import '../core/firebase_bootstrap.dart';

class SessionUser {
  final String uid;
  final String email;
  const SessionUser(this.uid, this.email);
}

abstract interface class AuthGateway {
  Stream<SessionUser?> get authStateChanges;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class AuthService implements AuthGateway {
  AuthService(this._auth);
  final FirebaseAuth _auth;
  static AuthService get instance => AuthService(FirebaseBootstrap.auth);

  @override
  Stream<SessionUser?> get authStateChanges => _auth.authStateChanges().map(
    (user) => user == null ? null : SessionUser(user.uid, user.email ?? ''),
  );
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

  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
  @override
  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Format email tidak valid.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email atau password salah.',
      'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
      'weak-password' || 'password-does-not-meet-requirements' =>
        'Password belum memenuhi kebijakan keamanan akun.',
      'network-request-failed' =>
        'Koneksi gagal. Periksa jaringan atau emulator.',
      'too-many-requests' =>
        'Terlalu banyak percobaan. Coba beberapa saat lagi.',
      'user-disabled' => 'Akun dinonaktifkan.',
      'operation-not-allowed' => 'Login email/password belum diaktifkan.',
      _ => 'Permintaan akun gagal. Silakan coba lagi.',
    };
  }
  return 'Layanan akun belum tersedia. Periksa konfigurasi Firebase.';
}

String? validateEmail(String? input) {
  final text = input?.trim() ?? '';
  if (text.isEmpty) return 'Email wajib diisi';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return 'Format email tidak valid';
  }
  return null;
}
