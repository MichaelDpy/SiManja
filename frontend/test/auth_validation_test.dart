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

  group('B03 kebijakan password', () {
    test('batas lokal sama dengan batas Firebase, tidak lebih lemah', () {
      expect(firebaseMinPasswordLength, 6);
      expect(localPasswordIssues('12345'), ['Minimal 6 karakter']);
      expect(localPasswordIssues('123456'), isEmpty);
      expect(localPasswordIssues('a' * 4097), ['Maksimal 4096 karakter']);
    });

    test('password tidak di-trim: spasi adalah bagian password', () {
      expect(localPasswordIssues('  abc '), isEmpty);
      expect(validateNewPassword('      '), isNull);
    });

    test('validator password baru', () {
      expect(validateNewPassword(''), 'Password wajib diisi');
      expect(validateNewPassword('abc'), contains('Minimal 6 karakter'));
      expect(validateNewPassword('Password123!'), isNull);
    });

    test('pesan kebijakan server diterjemahkan', () {
      expect(
        passwordPolicyMessage(
          'Missing password requirements: [Password must contain a lower '
          'case character, Password must contain an upper case character, '
          'Password must contain a numeric character, Password must contain '
          'a non-alphanumeric character, Password must contain at least 12 '
          'characters]',
        ),
        'Password belum memenuhi kebijakan: huruf kecil, huruf besar, angka, '
        'simbol, minimal 12 karakter.',
      );
      expect(
        passwordPolicyMessage(null),
        'Password belum memenuhi kebijakan keamanan akun.',
      );
      expect(
        authErrorMessage(
          FirebaseAuthException(
            code: 'password-does-not-meet-requirements',
            message: 'Missing password requirements: [upper case character]',
          ),
        ),
        'Password belum memenuhi kebijakan: huruf besar.',
      );
    });

    test('kode error tambahan dipetakan tanpa membocorkan akun', () {
      String m(String code) =>
          authErrorMessage(FirebaseAuthException(code: code));
      expect(m('user-not-found'), m('wrong-password'));
      expect(m('invalid-login-credentials'), 'Email atau password salah.');
      expect(m('user-disabled'), contains('dinonaktifkan'));
      expect(m('too-many-requests'), contains('Terlalu banyak'));
      expect(m('quota-exceeded'), contains('Terlalu banyak'));
      expect(m('expired-action-code'), contains('kedaluwarsa'));
      expect(m('invalid-action-code'), contains('sudah dipakai'));
      expect(m('requires-recent-login'), contains('masukkan ulang password'));
      expect(m(AuthErrorCodes.noCurrentUser), contains('Sesi berakhir'));
    });
  });
}
