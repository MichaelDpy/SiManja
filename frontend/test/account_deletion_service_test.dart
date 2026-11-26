import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/services/account_deletion_service.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/session_auth.dart';

/// B10: kontrak client permintaan hapus akun (tanpa jaringan).
void main() {
  const user = SessionUser('A', 'a@example.com');
  late List<({String name, Map<String, Object?> data})> calls;
  late Map<Object?, Object?> Function(String name) reply;
  Object? failure;

  setUp(() {
    calls = [];
    failure = null;
    reply = (_) => {'state': 'none'};
  });

  CloudAccountDeletionService service(SessionAuth auth) =>
      CloudAccountDeletionService((name, data) async {
        calls.add((name: name, data: data));
        if (failure != null) throw failure!;
        return reply(name);
      }, auth);

  test('status none diterjemahkan', () async {
    final status = await service(SessionAuth(currentUser: user)).status();
    expect(status.state, DeletionState.none);
    expect(calls.single.name, 'getAccountDeletionStatus');
  });

  test('permintaan mengirim requestId acak, tidak mengirim UID', () async {
    reply = (_) => {
      'state': 'requested',
      'requestId': 'req_x',
      'requestedAtMs': 1795000000000,
      'updatedAtMs': 1795000000000,
      'created': true,
    };
    final auth = SessionAuth(currentUser: user);
    final grant = await auth.reauthenticateWithPassword(
      'Password123!',
      SensitiveOperation.deleteAccount,
    );
    final status = await service(auth).request(grant);

    expect(status.state, DeletionState.requested);
    expect(status.created, isTrue);
    expect(status.requestedAt, isNotNull);
    expect(calls.single.name, 'requestAccountDeletion');
    expect(calls.single.data.keys, ['requestId']);
    expect(
      calls.single.data['requestId'],
      matches(RegExp(r'^req_[A-Za-z0-9]{24}$')),
    );
  });

  test(
    'requestId yang diberikan dipakai ulang (idempoten saat kirim ulang)',
    () async {
      final auth = SessionAuth(currentUser: user);
      final grant = await auth.reauthenticateWithPassword(
        'Password123!',
        SensitiveOperation.deleteAccount,
      );
      await service(auth).request(grant, requestId: 'req_tetap_123');
      expect(calls.single.data['requestId'], 'req_tetap_123');
    },
  );

  test(
    'grant operasi lain atau UID lain ditolak sebelum memanggil server',
    () async {
      final auth = SessionAuth(currentUser: user);
      final wrongOp = await auth.reauthenticateWithPassword(
        'Password123!',
        SensitiveOperation.changePassword,
      );
      final otherUid = ReauthGrant(
        uid: 'B',
        operation: SensitiveOperation.deleteAccount,
      );
      for (final grant in [wrongOp, otherUid]) {
        expect(
          () => service(auth).request(grant),
          throwsA(
            isA<AccountDeletionException>().having(
              (e) => e.requiresRecentLogin,
              'recent login',
              isTrue,
            ),
          ),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test('error server dipetakan dengan reason stabil', () async {
    failure = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'detail',
      details: {'reason': 'requires-recent-login'},
    );
    final auth = SessionAuth(currentUser: user);
    final grant = await auth.reauthenticateWithPassword(
      'Password123!',
      SensitiveOperation.deleteAccount,
    );
    try {
      await service(auth).request(grant);
      fail('seharusnya gagal');
    } on AccountDeletionException catch (error) {
      expect(error.requiresRecentLogin, isTrue);
      expect(accountDeletionErrorMessage(error), contains('verifikasi ulang'));
    }
  });

  test('state tak dikenal tidak dianggap selesai', () {
    final status = DeletionStatus.fromMap({'state': 'aneh'});
    expect(status.state, DeletionState.unknown);
    expect(status.state.accepted, isFalse);
    expect(DeletionState.requested.cancellable, isTrue);
    expect(DeletionState.processing.cancellable, isFalse);
  });

  test('pesan error lain', () {
    String m(String code, [String? reason]) =>
        accountDeletionErrorMessage(AccountDeletionException(code, reason));
    expect(
      m('failed-precondition', 'deletion-not-cancellable'),
      contains('tidak dapat dibatalkan'),
    );
    expect(m('unauthenticated'), contains('Sesi berakhir'));
    expect(m('unavailable'), contains('koneksi'));
    expect(m('internal'), contains('belum dapat diproses'));
  });
}
