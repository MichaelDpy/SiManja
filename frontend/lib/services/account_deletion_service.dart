import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

import '../core/firebase_bootstrap.dart';
import 'auth_service.dart';

/// Status siklus penghapusan akun dari layanan tepercaya (Cloud Functions).
/// Sama dengan `States` di backend/functions/src/deletion.js.
enum DeletionState {
  none,
  requested,
  processing,
  completed,
  failed,
  cancelled,
  unknown;

  static DeletionState parse(Object? value) => DeletionState.values.firstWhere(
    (state) => state.name == value,
    orElse: () => DeletionState.unknown,
  );

  /// Permintaan masih dapat dibatalkan pengguna.
  bool get cancellable => this == requested;

  /// Proses sudah diterima server (belum tentu selesai).
  bool get accepted => this == requested || this == processing;
}

class DeletionStatus {
  const DeletionStatus(
    this.state, {
    this.requestId,
    this.requestedAt,
    this.updatedAt,
    this.created = false,
  });

  final DeletionState state;
  final String? requestId;
  final DateTime? requestedAt;
  final DateTime? updatedAt;

  /// true bila panggilan ini membuat permintaan baru (bukan ulangan).
  final bool created;

  static DateTime? _time(Object? ms) =>
      ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;

  factory DeletionStatus.fromMap(Map<Object?, Object?> data) => DeletionStatus(
    DeletionState.parse(data['state']),
    requestId: data['requestId'] as String?,
    requestedAt: _time(data['requestedAtMs']),
    updatedAt: _time(data['updatedAtMs']),
    created: data['created'] == true,
  );
}

/// Kegagalan permintaan hapus akun dengan [reason] stabil dari server
/// (mis. `requires-recent-login`, `deletion-not-cancellable`).
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.code, [this.reason]);
  final String code;
  final String? reason;

  bool get requiresRecentLogin => reason == 'requires-recent-login';

  @override
  String toString() => 'AccountDeletionException($code, $reason)';
}

/// Kontrak client R-DELETE (B10). UI alur hapus akun dibangun di B13.
abstract interface class AccountDeletionGateway {
  Future<DeletionStatus> status();

  /// Meminta penghapusan akun sesi ini. Wajib [ReauthGrant] operasi
  /// [SensitiveOperation.deleteAccount]; server juga memeriksa umur login.
  Future<DeletionStatus> request(ReauthGrant grant, {String? requestId});

  /// Membatalkan selama status masih `requested`.
  Future<DeletionStatus> cancel();
}

/// Pemanggil callable; dapat diganti di tes. Melempar
/// [FirebaseFunctionsException] seperti SDK.
typedef CallableInvoker = Future<Map<Object?, Object?>> Function(
  String name,
  Map<String, Object?> data,
);

class CloudAccountDeletionService implements AccountDeletionGateway {
  CloudAccountDeletionService(this._invoke, this._auth);
  final CallableInvoker _invoke;
  final AuthGateway _auth;

  static CloudAccountDeletionService get instance =>
      CloudAccountDeletionService(
        firebaseInvoker(FirebaseBootstrap.functions),
        AuthService.instance,
      );

  static CallableInvoker firebaseInvoker(FirebaseFunctions functions) =>
      (name, data) async {
        final result = await functions
            .httpsCallable(
              name,
              options: HttpsCallableOptions(
                timeout: const Duration(seconds: 30),
              ),
            )
            .call<Map<Object?, Object?>>(data);
        return result.data;
      };

  /// Kunci idempotensi acak; pengiriman ulang permintaan yang sama memakai
  /// kunci yang sama sehingga server tidak membuat proses kedua.
  static String newRequestId() {
    final random = Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return 'req_${List.generate(24, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }

  Future<DeletionStatus> _call(String name, Map<String, Object?> data) async {
    try {
      return DeletionStatus.fromMap(await _invoke(name, data));
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason'] as String? : null;
      throw AccountDeletionException(error.code, reason);
    }
  }

  @override
  Future<DeletionStatus> status() => _call('getAccountDeletionStatus', {});

  @override
  Future<DeletionStatus> request(ReauthGrant grant, {String? requestId}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !grant.allows(uid, SensitiveOperation.deleteAccount)) {
      throw const AccountDeletionException(
        'failed-precondition',
        'requires-recent-login',
      );
    }
    // UID tidak dikirim: server memakai UID dari token Auth.
    return _call('requestAccountDeletion', {
      'requestId': requestId ?? newRequestId(),
    });
  }

  @override
  Future<DeletionStatus> cancel() => _call('cancelAccountDeletion', {});
}

/// Pesan Indonesia untuk kegagalan permintaan hapus akun.
String accountDeletionErrorMessage(Object error) {
  if (error is AccountDeletionException) {
    return switch (error.reason ?? error.code) {
      'requires-recent-login' =>
        'Demi keamanan, verifikasi ulang akun Anda lalu coba lagi.',
      'deletion-not-cancellable' =>
        'Penghapusan sudah diproses dan tidak dapat dibatalkan.',
      'account-disabled' || 'account-not-found' || 'unauthenticated' =>
        'Sesi berakhir atau akun tidak aktif. Silakan masuk kembali.',
      'invalid-request-id' => 'Permintaan tidak valid. Coba lagi.',
      'unavailable' || 'deadline-exceeded' =>
        'Layanan belum dapat dihubungi. Periksa koneksi lalu coba lagi.',
      _ => 'Permintaan hapus akun belum dapat diproses. Coba lagi nanti.',
    };
  }
  return 'Permintaan hapus akun belum dapat diproses. Coba lagi nanti.';
}
