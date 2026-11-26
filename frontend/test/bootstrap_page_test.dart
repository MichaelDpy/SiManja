import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simanja/core/firebase_environment.dart';
import 'package:simanja/screens/bootstrap_page.dart';

/// B01: status inisialisasi jujur — config salah tanpa retry palsu,
/// kegagalan runtime dapat dicoba ulang, sukses melanjutkan ke halaman awal.
void main() {
  Widget host(Future<void> Function() init) => MaterialApp(
    home: BootstrapPage(initialize: init, onReady: (_) => const Text('SIAP')),
  );

  testWidgets('loading lalu melanjutkan saat inisialisasi berhasil', (
    tester,
  ) async {
    final completer = Completer<void>();
    await tester.pumpWidget(host(() => completer.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('SIAP'), findsOneWidget);
  });

  testWidgets('config tidak valid menampilkan alasan tanpa tombol retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        () async => throw FirebaseConfigException(
          FirebaseEnvironment.production,
          ['Produksi tidak boleh memakai project demo-* milik emulator.'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Konfigurasi Firebase tidak valid'), findsOneWidget);
    expect(find.text('Lingkungan: Produksi'), findsOneWidget);
    expect(find.textContaining('project demo-*'), findsOneWidget);
    expect(find.text('Coba lagi'), findsNothing);
    expect(find.text('SIAP'), findsNothing);
  });

  testWidgets('kegagalan runtime dapat dicoba ulang hingga berhasil', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(() async {
        calls++;
        if (calls == 1) throw StateError('jaringan');
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('Firebase belum dapat disiapkan'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('SIAP'), findsOneWidget);
  });
}
