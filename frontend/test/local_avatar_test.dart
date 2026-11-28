import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/widgets/local_avatar.dart';

/// A1-11 — Pulihkan avatar saat decode atau file gagal.
///
/// Fixture korup / hilang / race + error capture (`tester.takeException`).
/// Fallback ikon pada helper (dipakai Profil & Dasbor).
void main() {
  // 1x1 PNG transparan valid.
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

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('a1_11_avatar');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget host(String? path) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SafeLocalAvatar(
          imagePath: path,
          radius: 24,
          backgroundColor: Colors.teal,
          fallbackIcon: Icons.person,
          fallbackIconColor: Colors.teal,
        ),
      ),
    ),
  );

  bool fallbackShown(WidgetTester tester) =>
      find.byIcon(Icons.person).evaluate().isNotEmpty;

  group('localImageFile', () {
    test('null/kosong → null', () {
      expect(localImageFile(null), isNull);
      expect(localImageFile(''), isNull);
      expect(localImageFile('   '), isNull);
    });
    test('file hilang → null (tidak menghapus apa pun)', () {
      final missing = '${tmp.path}/nope.png';
      expect(localImageFile(missing), isNull);
    });
    test('file ada → File; tidak menghapus file asli', () {
      final f = File('${tmp.path}/ok.png')..writeAsBytesSync(kTransparentPng);
      final out = localImageFile(f.path);
      expect(out, isNotNull);
      expect(out!.existsSync(), isTrue);
      expect(f.existsSync(), isTrue); // tidak menghapus foto asli
    });
  });

  testWidgets('tanpa foto → ikon fallback, tanpa error', (tester) async {
    await tester.pumpWidget(host(null));
    await tester.pumpAndSettle();
    expect(fallbackShown(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file hilang (missing) → ikon fallback, tanpa error', (
    tester,
  ) async {
    final missing = '${tmp.path}/does-not-exist.png';
    await tester.pumpWidget(host(missing));
    await tester.pumpAndSettle();
    expect(fallbackShown(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'file KORUP (decode gagal) → ikon fallback, tanpa error tak tertangani',
    (tester) async {
      final corrupt = File('${tmp.path}/corrupt.png')
        ..writeAsBytesSync(const [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x00,
          0x01,
          0x02,
          0xFF,
          0xFE,
          0x42,
        ]);
      // File ADA (existsSync=true) tapi tidak bisa di-decode.
      expect(corrupt.existsSync(), isTrue);
      await tester.pumpWidget(host(corrupt.path));
      await tester.pumpAndSettle();
      expect(fallbackShown(tester), isTrue);
      expect(tester.takeException(), isNull); // tidak ada error tak tertangani
      expect(corrupt.existsSync(), isTrue); // foto asli tidak dihapus
    },
  );

  testWidgets('konten non-gambar (teks) yang exists → fallback, tanpa error', (
    tester,
  ) async {
    final notImage = File('${tmp.path}/note.png')
      ..writeAsStringSync('this is not an image at all');
    await tester.pumpWidget(host(notImage.path));
    await tester.pumpAndSettle();
    expect(fallbackShown(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'RACE: file hilang SETELAH exists-check → fallback, tanpa error',
    (tester) async {
      final f = File('${tmp.path}/race.png')..writeAsBytesSync(kTransparentPng);
      expect(f.existsSync(), isTrue);
      // existsSync=true saat pemeriksaan pertama...
      await tester.pumpWidget(host(f.path));
      await tester.pump();
      // ...tapi file hilang SETELAH exists-check / sebelum read / render.
      f.deleteSync();
      await tester.pumpWidget(
        host(f.path),
      ); // rebuild: readLocalImageBytes→null
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // tidak ada error tak tertangani
      expect(fallbackShown(tester), isTrue); // fallback ikon
      expect(f.existsSync(), isFalse);
      expect(f.existsSync(), isFalse); // tidak membuat/memasang ulang file
    },
  );

  testWidgets('file gambar valid → tampil tanpa error & fallback tidak paksa', (
    tester,
  ) async {
    final ok = File('${tmp.path}/ok.png')..writeAsBytesSync(kTransparentPng);
    await tester.pumpWidget(host(ok.path));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ok.existsSync(), isTrue);
    // CircleAvatar ada; tidak ada error. (fallback tidak menggantikan saat OK.)
    expect(find.byType(CircleAvatar), findsOneWidget);
  });
}
