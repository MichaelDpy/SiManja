import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

enum SyncFailureKind {
  unavailable,
  permissionDenied,
  unauthenticated,
  timeout,
  unknown,
}

/// A failed Future is not proof that a request never reached the server.
/// No SDK message/path/record content is exposed to the UI.
class SyncFailure extends StateError {
  SyncFailure(this.kind, {required this.mayHaveCommitted}) : super('');
  final SyncFailureKind kind;
  final bool mayHaveCommitted;

  factory SyncFailure.from(Object error, {bool forceUnconfirmed = false}) {
    if (error is SyncFailure && !forceUnconfirmed) return error;
    final kind = error is SyncFailure
        ? error.kind
        : error is TimeoutException
        ? SyncFailureKind.timeout
        : error is FirebaseException
        ? switch (error.code) {
            'permission-denied' => SyncFailureKind.permissionDenied,
            'unauthenticated' => SyncFailureKind.unauthenticated,
            'unavailable' ||
            'network-request-failed' => SyncFailureKind.unavailable,
            'deadline-exceeded' => SyncFailureKind.timeout,
            _ => SyncFailureKind.unknown,
          }
        : SyncFailureKind.unknown;
    return SyncFailure(
      kind,
      mayHaveCommitted:
          forceUnconfirmed ||
          (kind != SyncFailureKind.permissionDenied &&
              kind != SyncFailureKind.unauthenticated),
    );
  }

  @override
  String get message {
    if (mayHaveCommitted) {
      return 'Hasil penyimpanan belum dapat dipastikan. Muat data server sebelum mengirim ulang; perubahan mungkin sudah tersimpan.';
    }
    return kind == SyncFailureKind.permissionDenied
        ? 'Perubahan ditolak karena izin akun. Draft tetap tersedia; periksa akses akun sebelum mencoba lagi.'
        : 'Sesi akun tidak valid. Masuk kembali sebelum mencoba menyimpan.';
  }

  String get loadMessage => switch (kind) {
    SyncFailureKind.permissionDenied =>
      'Akses profil ditolak. Periksa izin akun sebelum memuat ulang.',
    SyncFailureKind.unauthenticated =>
      'Sesi akun tidak valid. Masuk kembali untuk memuat profil.',
    _ => 'Profil belum dapat dikonfirmasi server. Periksa koneksi lalu muat ulang.',
  };
  @override
  String toString() => message;
}
