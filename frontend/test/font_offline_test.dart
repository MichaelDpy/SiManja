import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:simanja/core/theme.dart';

/// A1-17: Lato dimuat dari aset aplikasi tanpa jaringan.
///
/// google_fonts tidak melempar error bila font tidak ditemukan; ia hanya
/// mencetak pesan lalu diam-diam memakai font sistem. Tes ini menangkap pesan
/// tersebut dan memblokir semua HTTP agar regresi tidak lolos tanpa terlihat.
void main() {
  late HttpOverrides? previousOverrides;
  final printed = <String>[];
  var httpAttempts = 0;

  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _BlockAllHttp(() => httpAttempts++);
    // Sama dengan main.dart: tidak ada unduhan font saat runtime.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDownAll(() => HttpOverrides.global = previousOverrides);

  setUp(printed.clear);

  /// Menjalankan [body] sambil merekam print() dari google_fonts.
  Future<void> capturePrints(Future<void> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => printed.add(line),
    ),
  );

  List<String> fontErrors() =>
      printed.where((line) => line.contains('unable to load font')).toList();

  test('seluruh ketebalan Lato (100–900) tersedia sebagai aset', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets().toSet();
    for (final name in [
      'Thin',
      'ExtraLight',
      'Light',
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
      'Black',
    ]) {
      expect(assets, contains('assets/fonts/Lato-$name.ttf'), reason: name);
    }
  });

  test(
    'ketebalan yang dipakai UI dimuat tanpa jaringan dan tanpa error',
    () async {
      await capturePrints(() async {
        final styles = [
          for (final weight in FontWeight.values)
            GoogleFonts.lato(fontWeight: weight),
        ];
        await GoogleFonts.pendingFonts(styles);
      });
      expect(fontErrors(), isEmpty, reason: printed.join('\n'));
      expect(httpAttempts, 0, reason: 'font tidak boleh diunduh');
    },
  );

  testWidgets('tema terang dan gelap merender tanpa unduhan font', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await capturePrints(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('SIMANJA')),
              body: Column(
                children: [
                  for (final weight in const [
                    FontWeight.w400,
                    FontWeight.w500,
                    FontWeight.w600,
                    FontWeight.w700,
                    FontWeight.w800,
                    FontWeight.w900,
                  ])
                    Text(
                      'Rp 1.000.000',
                      style: GoogleFonts.lato(fontWeight: weight),
                    ),
                  FilledButton(onPressed: () {}, child: const Text('Simpan')),
                  const TextField(
                    decoration: InputDecoration(labelText: 'Keterangan'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.runAsync(() => GoogleFonts.pendingFonts());
        await tester.pump();
      });
    }
    expect(fontErrors(), isEmpty, reason: printed.join('\n'));
    expect(httpAttempts, 0);
    expect(tester.takeException(), isNull);
  });

  test('lisensi OFL Lato tersedia untuk halaman lisensi', () async {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    expect(license, contains('SIL OPEN FONT LICENSE'));
    expect(license, contains('Lato'));
  });
}

/// Setiap koneksi HTTP keluar dianggap kegagalan tes.
class _BlockAllHttp extends HttpOverrides {
  _BlockAllHttp(this.onAttempt);
  final void Function() onAttempt;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    onAttempt();
    throw const SocketException('Jaringan diblokir pada tes font offline');
  }
}
