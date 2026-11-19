import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/models/user_profile.dart';
import 'package:simanja/repositories/profile_repository.dart';

import 'support/memory_profiles.dart';

Future<void> saveName(AppState state, String name, {String? email}) =>
    state.updateProfile(
      newName: name,
      newEmail: email ?? state.email,
      newPhone: state.phone,
      newAddress: state.address,
      newCity: state.city,
      newJob: state.job,
      newIncome: state.monthlyIncome,
    );

void main() {
  late MemoryProfiles repository;
  late AppState state;
  setUp(() {
    repository = MemoryProfiles();
    state = AppState.forTesting(profiles: repository);
  });
  tearDown(() => state.dispose());

  test(
    'profil dimuat sekali per sesi, perubahan bertahan setelah login ulang',
    () async {
      await state.beginSession('A', 'a@example.com');
      await saveName(state, 'Nama Baru');
      await state.beginSession('A', 'a@example.com');
      expect(repository.loadCalls, 1);
      state.clearSession();
      await state.beginSession('A', 'a@example.com');
      expect(state.name, 'Nama Baru');
      expect(repository.profiles, hasLength(1));
      expect(state.email, 'a@example.com');
    },
  );
  test('write ditunggu; kegagalan mempertahankan profil lama', () async {
    await state.beginSession('A', 'a@example.com');
    repository.pendingSave = Completer<void>();
    final request = saveName(state, 'Nama Baru');
    expect(state.profileSaving, isTrue);
    expect(state.name, 'a');
    repository.saveFailure = StateError('denied');
    final failure = expectLater(request, throwsStateError);
    repository.pendingSave!.complete();
    await failure;
    expect(state.name, 'a');
    expect(state.profileSaving, isFalse);
  });
  test('preferensi hanya berubah setelah server menyetujui', () async {
    await state.beginSession('A', 'a@example.com');
    repository.pendingSave = Completer<void>();
    final request = state.setDarkMode(false);
    expect(state.darkMode, isTrue);
    expect(state.profileSaving, isTrue);
    repository.pendingSave!.complete();
    await request;
    expect(state.darkMode, isFalse);
    state.clearSession();
    await state.beginSession('A', 'a@example.com');
    expect(state.darkMode, isFalse);
  });
  test(
    'perubahan preferensi tidak menimpa field cloud yang tidak diedit',
    () async {
      await state.beginSession('A', 'a@example.com');
      repository.profiles['A'] = repository.profiles['A']!.copyWith(
        city: 'Kota dari perangkat lain',
      );
      await state.setNotif(false);
      expect(repository.saves.single.changes, {'notifEnabled': false});
      expect(repository.profiles['A']!.city, 'Kota dari perangkat lain');
    },
  );
  test('hasil load A yang terlambat tidak mengisi profil B', () async {
    repository.delayedLoads['A'] = Completer<UserProfile>();
    final loadA = state.beginSession('A', 'a@example.com');
    expect(state.profileLoading, isTrue);
    state.clearSession();
    await state.beginSession('B', 'b@example.com');
    repository.delayedLoads['A']!.complete(
      const UserProfile(name: 'Rahasia A'),
    );
    await loadA;
    expect(state.name, 'b');
    expect(state.profileReady, isTrue);
    expect(state.profileLoading, isFalse);
    expect(state.email, 'b@example.com');
  });
  test('hasil write A tidak mengubah akun B setelah logout', () async {
    await state.beginSession('A', 'a@example.com');
    repository.pendingSave = Completer<void>();
    final request = saveName(state, 'Nama A');
    final rejected = expectLater(request, throwsStateError);
    state.clearSession();
    await state.beginSession('B', 'b@example.com');
    repository.pendingSave!.complete();
    await rejected;
    expect(state.name, 'b');
    expect(state.sessionUid, 'B');
    expect(state.profileSaving, isFalse);
    expect(repository.profiles['A']!.name, 'Nama A');
  });
  test(
    'load gagal tidak memakai profil dummy dan dapat dicoba ulang',
    () async {
      repository.loadFailure = StateError('offline');
      await state.beginSession('A', 'a@example.com');
      expect(state.profileReady, isFalse);
      expect(state.profileError, isNotNull);
      expect(state.phone, isEmpty);
      repository.loadFailure = null;
      repository.profiles['A'] = const UserProfile(
        name: 'Dari server',
        city: 'Bandung',
      );
      await state.retryProfile();
      expect(state.profileReady, isTrue);
      expect(state.profileError, isNull);
      expect(state.name, 'Dari server');
    },
  );
  test(
    'load ganda dan submit ganda tidak mengirim request bersamaan',
    () async {
      repository.delayedLoads['A'] = Completer<UserProfile>();
      final first = state.beginSession('A', 'a@example.com');
      final second = state.retryProfile();
      expect(repository.loadCalls, 1);
      repository.profiles['A'] = const UserProfile(name: 'Akun A');
      repository.delayedLoads['A']!.complete(repository.profiles['A']!);
      await Future.wait([first, second]);
      repository.pendingSave = Completer<void>();
      final save = state.setNotif(false);
      await expectLater(state.setDarkMode(false), throwsStateError);
      expect(repository.saves, hasLength(1));
      repository.pendingSave!.complete();
      await save;
    },
  );
  test('email identitas tidak bisa diubah melalui profil', () async {
    await state.beginSession('A', 'a@example.com');
    await expectLater(
      saveName(state, 'Nama', email: 'other@example.com'),
      throwsArgumentError,
    );
    expect(state.email, 'a@example.com');
    expect(repository.saves, isEmpty);
  });
  test('schema hanya menyimpan profil/preferensi dan nominal integer', () {
    final data = const UserProfile(name: 'Nama', monthlyIncome: 1000).toMap();
    expect(data['monthlyIncome'], isA<int>());
    expect(data.keys.toSet(), {
      'name',
      'phone',
      'address',
      'city',
      'job',
      'monthlyIncome',
      'darkMode',
      'notifEnabled',
    });
    expect(
      () => UserProfile.fromMap({...data, 'monthlyIncome': '1000'}),
      throwsFormatException,
    );
    for (final amount in [
      -1.0,
      0.5,
      double.nan,
      double.infinity,
      9007199254740992.0,
    ]) {
      expect(
        () => UserProfile(name: 'Nama', monthlyIncome: amount).toMap(),
        throwsArgumentError,
      );
    }
  });
  test(
    'parser rupiah menolak pecahan dan separator ambigu tanpa mengubah nilai',
    () {
      expect(UserProfile.parseIncome(''), 0);
      expect(UserProfile.parseIncome('5000000'), 5000000);
      expect(UserProfile.parseIncome('5.000.000'), 5000000);
      for (final raw in [
        '1,5',
        '1.5',
        '1.000,50',
        '-1',
        'NaN',
        'Infinity',
        'Rp 1000',
        '1e3',
      ]) {
        expect(UserProfile.parseIncome(raw), isNull, reason: raw);
      }
    },
  );
  test('repository menolak UID path lain sebelum akses database', () async {
    final repository = FirestoreProfileRepository.lazy(
      () => throw StateError('Tidak boleh mengakses SDK'),
    );
    await expectLater(
      repository.loadOrCreate('A/other', 'a@example.com'),
      throwsArgumentError,
    );
  });
  test(
    'load yang selesai setelah state dilepas tidak memberi notifikasi',
    () async {
      final lateRepository = MemoryProfiles();
      lateRepository.delayedLoads['A'] = Completer<UserProfile>();
      final closingState = AppState.forTesting(profiles: lateRepository);
      final request = closingState.beginSession('A', 'a@example.com');
      closingState.dispose();
      lateRepository.delayedLoads['A']!.complete(
        const UserProfile(name: 'Nama'),
      );
      await request;
    },
  );
}
