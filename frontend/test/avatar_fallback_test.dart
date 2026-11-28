import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/screens/dashboard_page.dart';
import 'package:simanja/screens/profile_page.dart';
import 'package:simanja/services/auth_service.dart';
import 'package:simanja/widgets/local_avatar.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

/// A1-11 — fallback ikon pada Profil DAN Dasbor (corrupt/missing/race).
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
  late Directory tmp;
  late SessionAuth auth;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('a1_11_fallback');
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
    state.clearSession();
    state.useProfileRepository(MemoryProfiles());
    state.useTransactionRepository(MemoryTransactions());
  });
  tearDown(() async {
    await auth.events.close();
    state.clearSession();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String corruptPath() {
    final f = File(
      '${tmp.path}/corrupt.png',
    )..writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0xFF, 0xFE]);
    return f.path;
  }

  test('readLocalImageBytes: korup→bytes (decode di Image.memory); hilang→null; tidak hapus', () {
    final corrupt = corruptPath();
    final bytes = readLocalImageBytes(corrupt);
    expect(bytes, isNotNull); // file ada; decode gagal di Image.memory
    expect(File(corrupt).existsSync(), isTrue); // tidak menghapus foto asli
    expect(readLocalImageBytes('${tmp.path}/missing.png'), isNull);
    expect(readLocalImageBytes(null), isNull);
    expect(readLocalImageBytes(''), isNull);
    // tidak membuat file
    expect(File('${tmp.path}/missing.png').existsSync(), isFalse);
  });

  Future<void> pumpProfile(WidgetTester tester) async {
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

  testWidgets('Profil: file korup → fallback ikon person tanpa error', (
    tester,
  ) async {
    await pumpProfile(tester);
    state.updatePhoto(corruptPath());
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byIcon(Icons.person), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dasbor: file korup → fallback ikon person tanpa error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    state.updatePhoto(corruptPath());
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byIcon(Icons.person), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profil & Dasbor: file hilang → fallback tanpa error', (
    tester,
  ) async {
    await pumpProfile(tester);
    state.updatePhoto('${tmp.path}/nope.png');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foto valid tidak error & profil utuh', (tester) async {
    await pumpProfile(tester);
    final ok = File('${tmp.path}/ok.png')..writeAsBytesSync(kTransparentPng);
    state.updatePhoto(ok.path);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ok.existsSync(), isTrue);
    expect(state.photoPath, ok.path);
  });
}
