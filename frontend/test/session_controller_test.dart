import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/session_controller.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/session_auth.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
TransactionModel transaction(String id) => TransactionModel(
  id: id,
  category: 'Gaji',
  description: 'Data sesi',
  amount: 1000,
  isIncome: true,
  date: DateTime(2026, 11, 19),
);

void main() {
  late SessionAuth auth;
  late AppState state;
  late SessionController controller;
  setUp(() {
    auth = SessionAuth(emitInitial: false);
    state = AppState.forTesting();
    controller = SessionController(auth, state: state);
  });
  tearDown(() async {
    controller.dispose();
    await auth.events.close();
    state.dispose();
  });

  test('belum ada snapshot sesi berarti checking, bukan akses Home', () async {
    await tick();
    expect(controller.checking, isTrue);
    expect(controller.user, isNull);
    expect(state.transactions, isEmpty);
  });
  test('identitas UID dipulihkan tanpa profil/transaksi dummy', () async {
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    expect(controller.checking, isFalse);
    expect(controller.user!.uid, 'A');
    expect(state.sessionUid, 'A');
    expect(state.email, 'a@example.com');
    expect(state.name, 'a');
    expect(state.phone, isEmpty);
    expect(state.monthlyIncome, 0);
    expect(state.transactions, isEmpty);
  });
  test('emisi UID sama mempertahankan perubahan lokal sesi', () async {
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    await state.addTransaction(transaction('private-A'));
    state.updatePhoto('photo-A');
    final revision = state.sessionRevision;
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    expect(state.transactions.single.id, 'private-A');
    expect(state.photoPath, 'photo-A');
    expect(state.sessionRevision, revision);
  });
  test(
    'UID berubah menghapus data akun lama dan mempertahankan tema perangkat',
    () async {
      auth.emit(const SessionUser('A', 'a@example.com'));
      await tick();
      state.phone = '08123456789';
      state.monthlyIncome = 123;
      await state.setDarkMode(false);
      await state.setNotif(false);
      state.updatePhoto('private-photo');
      await state.addTransaction(transaction('private-A'));
      final revision = state.sessionRevision;
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tick();
      expect(state.sessionUid, 'B');
      expect(state.email, 'b@example.com');
      expect(state.phone, isEmpty);
      expect(state.monthlyIncome, 0);
      expect(state.photoPath, isNull);
      expect(state.transactions, isEmpty);
      expect(state.notifEnabled, isTrue);
      expect(state.darkMode, isFalse);
      expect(state.sessionRevision, greaterThan(revision));
    },
  );
  test('logout nyata ditunggu dan tidak dapat dikirim ganda', () async {
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    await state.addTransaction(transaction('private-A'));
    auth.pendingSignOut = Completer<void>();
    final request = controller.signOut();
    await controller.signOut();
    expect(auth.signOutCalls, 1);
    expect(controller.signingOut, isTrue);
    expect(controller.user!.uid, 'A');
    auth.pendingSignOut!.complete();
    await request;
    await tick();
    expect(controller.user, isNull);
    expect(state.sessionUid, isNull);
    expect(state.transactions, isEmpty);
  });
  test('logout gagal tidak berpura-pura mengakhiri sesi', () async {
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    state.updatePhoto('photo-A');
    auth.signOutFailure = StateError('offline');
    await expectLater(controller.signOut(), throwsStateError);
    expect(controller.user!.uid, 'A');
    expect(state.photoPath, 'photo-A');
    expect(controller.signingOut, isFalse);
  });
  test(
    'hasil logout lama tidak menghapus akun baru yang sudah aktif',
    () async {
      auth.emit(const SessionUser('A', 'a@example.com'));
      await tick();
      auth.pendingSignOut = Completer<void>();
      auth.emitSignOutEvent = false;
      final request = controller.signOut();
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tick();
      auth.pendingSignOut!.complete();
      await request;
      expect(controller.user!.uid, 'B');
      expect(state.sessionUid, 'B');
    },
  );
  test(
    'error stream membersihkan data; retry mengabaikan event langganan lama',
    () async {
      auth.emit(const SessionUser('A', 'a@example.com'));
      await tick();
      state.updatePhoto('photo-A');
      auth.events.addError(StateError('lost connection'));
      await tick();
      expect(controller.error, isNotNull);
      expect(controller.user, isNull);
      expect(state.photoPath, isNull);
      controller.retry();
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tick();
      expect(controller.user!.uid, 'B');
      expect(controller.error, isNull);
    },
  );
  test(
    'stream berakhir tanpa snapshot tidak menyisakan spinner tanpa akhir',
    () async {
      await auth.events.close();
      await tick();
      expect(controller.checking, isFalse);
      expect(controller.error, isNotNull);
    },
  );
  test('retry setelah logout tidak mengisi ulang data demo', () async {
    auth.emit(const SessionUser('A', 'a@example.com'));
    await tick();
    await state.addTransaction(transaction('private-A'));
    await controller.signOut();
    await tick();
    await state.retryTransactions();
    expect(state.transactions, isEmpty);
    expect(state.name, isEmpty);
    expect(state.email, isEmpty);
  });
}
