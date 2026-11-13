import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simanja/core/mock_data.dart';
import 'package:simanja/screens/asset_page.dart';

void main() {
  // ── AssetCalculator Unit Tests ───────────────────────────────────────────
  group('AssetCalculator', () {
    const testAssets = [
      AssetModel(
        name: 'Rekening Bank',
        value: 20000000,
        percentage: 0,
        color: Colors.blue,
      ),
      AssetModel(
        name: 'Investasi',
        value: 30000000,
        percentage: 0,
        color: Colors.green,
      ),
      AssetModel(
        name: 'Tabungan',
        value: 50000000,
        percentage: 0,
        color: Colors.orange,
      ),
    ];

    test('calculateTotal mengembalikan jumlah seluruh nilai aset', () {
      final total = AssetCalculator.calculateTotal(testAssets);
      expect(total, 100000000.0);
    });

    test('calculateTotal mengembalikan 0.0 untuk daftar kosong', () {
      final total = AssetCalculator.calculateTotal([]);
      expect(total, 0.0);
    });

    test('calculatePercentage menghitung persentase secara proporsional', () {
      final pct = AssetCalculator.calculatePercentage(30000000, 100000000);
      expect(pct, closeTo(30.0, 0.001));
    });

    test('calculatePercentage menangani total nol tanpa crash/NaN', () {
      final pct = AssetCalculator.calculatePercentage(1000, 0);
      expect(pct, 0.0);
      expect(pct.isNaN, isFalse);
      expect(pct.isInfinite, isFalse);
    });

    test('calculatePercentage menangani nilai negatif/nol', () {
      expect(AssetCalculator.calculatePercentage(0, 100000), 0.0);
      expect(AssetCalculator.calculatePercentage(-500, 100000), 0.0);
    });

    test('filterByCategory mengembalikan seluruh aset jika kategori null atau Semua', () {
      expect(
        AssetCalculator.filterByCategory(testAssets, null).length,
        testAssets.length,
      );
      expect(
        AssetCalculator.filterByCategory(testAssets, '').length,
        testAssets.length,
      );
      expect(
        AssetCalculator.filterByCategory(testAssets, 'Semua').length,
        testAssets.length,
      );
    });

    test('filterByCategory menyaring sesuai kategori yang dipilih', () {
      final filtered = AssetCalculator.filterByCategory(testAssets, 'Investasi');
      expect(filtered.length, 1);
      expect(filtered.first.name, 'Investasi');
      expect(filtered.first.value, 30000000.0);
    });

    test('filterByCategory mengembalikan list kosong jika kategori tidak ada', () {
      final filtered = AssetCalculator.filterByCategory(testAssets, 'Properti');
      expect(filtered.isEmpty, isTrue);
    });

    test('getScopeLabel menjelaskan cakupan dengan benar', () {
      expect(
        AssetCalculator.getScopeLabel(null),
        'Total Nilai Aset (Semua Kategori)',
      );
      expect(
        AssetCalculator.getScopeLabel('Semua'),
        'Total Nilai Aset (Semua Kategori)',
      );
      expect(
        AssetCalculator.getScopeLabel('Investasi'),
        'Total Nilai Aset (Investasi)',
      );
    });
  });

  // ── AssetPage Widget Tests ───────────────────────────────────────────────
  group('AssetPage Widget Tests', () {
    testWidgets('menampilkan Total Nilai Aset dan menghapus klaim fiktif', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssetPage(),
        ),
      );
      await tester.pump();

      // Memastikan label Aset Bersih telah diganti menjadi Total Nilai Aset
      expect(find.textContaining('Total Nilai Aset'), findsOneWidget);
      expect(find.text('Total Aset Bersih'), findsNothing);

      // Memastikan klaim pertumbuhan fiktif telah dihapus
      expect(find.text('+4.2% bulan ini'), findsNothing);

      // Memastikan keterangan data contoh hadir
      expect(
        find.text('Data contoh • belum tersinkron dengan transaksi'),
        findsOneWidget,
      );

      // Memastikan total nominal awal sesuai MockData (Rp 86.500.000)
      expect(find.textContaining('86.500.000'), findsWidgets);
    });

    testWidgets('filter kategori melalui chip memperbarui total dan daftar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AssetPage(),
        ),
      );
      await tester.pump();

      // Pilih chip Investasi
      final investasiChip = find.widgetWithText(ChoiceChip, 'Investasi');
      expect(investasiChip, findsOneWidget);

      await tester.tap(investasiChip);
      await tester.pump();

      // Label total terfilter menjelaskan cakupannya
      expect(find.text('Total Nilai Aset (Investasi)'), findsOneWidget);

      // Total terfilter menjadi Rp 32.000.000
      expect(find.textContaining('32.000.000'), findsWidgets);
      expect(find.text('1 Aset'), findsOneWidget);

      // Reset filter via chip Semua
      final semuaChip = find.widgetWithText(ChoiceChip, 'Semua (5)');
      await tester.tap(semuaChip);
      await tester.pump();

      // Kembali ke semua aset
      expect(
        find.text('Total Nilai Aset (Semua Kategori)'),
        findsOneWidget,
      );
      expect(find.textContaining('86.500.000'), findsWidgets);
      expect(find.text('5 Aset'), findsOneWidget);
    });

    testWidgets('aman dirender pada lebar 320 logical pixels tanpa overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: AssetPage(),
        ),
      );
      await tester.pump();

      expect(find.byType(AssetPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aman dirender pada skala teks 1.5 tanpa crash', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: AssetPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AssetPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
