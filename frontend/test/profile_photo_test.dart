import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// A1-11 — picker cancel/permission/error + sessionRevision async + tidak
/// menghapus profil + tidak memasang foto A di B.
void main() {
  const kTransparentPng = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
    0x42, 0x60, 0x82,
  ];

  final state = AppState.instance;
  late MemoryProfiles profiles;
  late SessionAuth auth;
  late _FakePicker picker;
  late ImagePickerPlatform previousPicker;
  late Directory tmp;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    profiles = MemoryProfiles();
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
    picker = _FakePicker();
    previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    tmp = Directory.systemTemp.createTempSync('a1_11_picker');
    state.clearSession();
    state.useProfileRepository(profiles);
    state.useTransactionRepository(MemoryTransactions());
  });

  tearDown(() async {
    ImagePickerPlatform.instance = previousPicker;
    await auth.events.close();
    state.clearSession();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> openProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Profil'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openGallery(WidgetTester tester) async {
    // avatar → sheet → Galeri
    final avatar = find.byType(CircleAvatar).first;
    await tester.ensureVisible(avatar);
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galeri'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'CANCEL picker: img null → tidak ada aksi; profil tidak dihapus',
    (tester) async {
      await openProfile(tester);
      picker.result = null; // pengguna membatalkan
      final before = profiles.profiles['A'];
      await openGallery(tester);
      expect(picker.calls, 1);
      expect(state.photoPath, isNull); // profil foto tidak dihapus/diset
      expect(profiles.profiles['A'], before); // profil tidak diubah
      expect(profiles.saves, isEmpty); // tidak ada write
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PERMISSION galeri ditolak → pesan; profil tidak dihapus', (
    tester,
  ) async {
    await openProfile(tester);
    picker.error = PlatformException(
      code: 'photo_access_denied',
      message: 'denied',
    );
    await openGallery(tester);
    expect(find.textContaining('Izin galeri ditolak'), findsOneWidget);
    expect(state.photoPath, isNull);
    expect(profiles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PERMISSION kamera ditolak → pesan kamera; profil tidak dihapus',
    (tester) async {
      await openProfile(tester);
      picker.error = PlatformException(
        code: 'camera_access_denied',
        message: 'denied',
      );
      // kamera
      final avatar = find.byType(CircleAvatar).first;
      await tester.ensureVisible(avatar);
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Izin kamera ditolak'), findsOneWidget);
      expect(state.photoPath, isNull);
      expect(profiles.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ERROR picker (non-permission) → pesan; profil tidak dihapus', (
    tester,
  ) async {
    await openProfile(tester);
    picker.error = PlatformException(code: 'camera_error', message: 'boom');
    await openGallery(tester);
    expect(find.textContaining('Gagal memilih foto'), findsOneWidget);
    expect(state.photoPath, isNull);
    expect(profiles.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'UID switch: picker selesai setelah UID berubah tidak memasang foto A di B',
    (tester) async {
      await openProfile(tester);
      // file A valid
      final aFile = File('${tmp.path}/a.png')
        ..writeAsBytesSync(kTransparentPng);
      picker.pending = Completer<XFile?>();
      await openGallery(tester); // _pickFromSource captured revision sesi A
      expect(picker.calls, 1);

      // UID berubah ke B SAAT picker belum selesai
      profiles.profiles['B'] = profiles.profiles['A']!.copyWith(name: 'Nama B');
      auth.emit(const SessionUser('B', 'b@example.com'));
      await tester.pumpAndSettle();
      expect(state.sessionUid, 'B');

      // picker sesi A selesai sekarang dengan file A
      picker.pending!.complete(XFile(aFile.path));
      await tester.pumpAndSettle();

      // Tidak memasang foto A di B; profil B tidak tersentuh; tidak ada feedback A
      expect(state.photoPath, isNull);
      expect(profiles.saves, isEmpty);
      expect(find.textContaining('Gagal memilih foto'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CANCEL picker pada sesi: tidak ada aksi & tidak ada write ganda',
    (tester) async {
      await openProfile(tester);
      picker.result = null;
      await openGallery(tester);
      await openGallery(tester); // kedua kali juga cancel
      expect(state.photoPath, isNull);
      expect(profiles.saves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Mock `ImagePickerPlatform` (extends, karena `PlatformInterface.verify`).
class _FakePicker extends ImagePickerPlatform {
  XFile? result;
  Object? error;
  Completer<XFile?>? pending;
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    final pendingCompleter = pending;
    if (pendingCompleter != null) return pendingCompleter.future;
    final err = error;
    if (err != null) throw err;
    return result;
  }
}
