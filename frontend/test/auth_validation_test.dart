import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/services/auth_service.dart';

void main() {
  test('email menolak spasi dan format tidak lengkap', () {
    expect(validateEmail(' user@example.com '), isNull);
    for (final input in ['', 'abc', 'a@b', 'a b@example.com']) {
      expect(validateEmail(input), isNotNull);
    }
  });
  test('pesan error tidak menampilkan detail kredensial dari SDK', () {
    expect(
      authErrorMessage(
        FirebaseAuthException(
          code: 'wrong-password',
          message: 'sensitive SDK detail',
        ),
      ),
      'Email atau password salah.',
    );
    expect(
      authErrorMessage(FirebaseAuthException(code: 'network-request-failed')),
      contains('Koneksi gagal'),
    );
  });
}
