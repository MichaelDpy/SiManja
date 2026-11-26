import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/theme.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/screens/data_table_page.dart';
import 'package:simanja/screens/main_shell.dart';

/// Regresi integrasi A8: keenam tab tidak boleh overflow pada layar sempit,
/// landscape, skala teks 1,5, serta tema terang/gelap; state tab bertahan
/// saat rotasi.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  setUp(() => AppState.instance.reset());

  const sizes = <String, Size>{
    '320x640': Size(320, 640),
    '360x780': Size(360, 780),
    '412x900': Size(412, 900),
    'landscape 800x360': Size(800, 360),
  };
  const tabIcons = [
    Icons.dashboard_outlined,
    Icons.donut_large_outlined,
    Icons.swap_horiz_outlined,
    Icons.table_chart_outlined,
    Icons.bar_chart_outlined,
    Icons.person_outline,
  ];

  Widget app({required bool dark, double scale = 1.0}) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: const MainShell(),
  );

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 1.5]) {
      for (final dark in [false, true]) {
        final label = '${entry.key}, teks $scale, ${dark ? 'gelap' : 'terang'}';
        testWidgets('enam tab tanpa overflow: $label', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final errors = <String>[];
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final source = RegExp(r'lib/[\w/]+\.dart:\d+')
                .firstMatch(details.toString())
                ?.group(0);
            errors.add(
              '${details.exceptionAsString().split('\n').first} @ $source',
            );
          };
          addTearDown(() => FlutterError.onError = previous);

          await tester.pumpWidget(app(dark: dark, scale: scale));
          await tester.pump();

          for (final icon in tabIcons) {
            final finder = find.byIcon(icon);
            if (finder.evaluate().isEmpty) continue;
            await tester.tap(finder.first, warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 400));
          }

          FlutterError.onError = previous;
          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }
  }

  testWidgets('state tab bertahan saat rotasi portrait ↔ landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(dark: true));
    await tester.tap(find.byIcon(Icons.table_chart_outlined));
    await tester.pump();
    final before = tester.state(find.byType(DataTablePage));

    tester.view.physicalSize = const Size(900, 412);
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.state(find.byType(DataTablePage)), same(before));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      3,
    );

    tester.view.physicalSize = const Size(412, 900);
    await tester.pump();
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.state(find.byType(DataTablePage)), same(before));
  });

  testWidgets('periode dasbor kembali ke Semua bila tergeser CRUD', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = AppState.instance;
    await tester.pumpWidget(app(dark: false));
    await tester.pump();

    // Pilih chip bulan paling lama dari rentang enam bulan.
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(7));
    final oldest = tester.widget<ChoiceChip>(chips.last);
    final oldestLabel = (oldest.label as Text).data!;
    await tester.ensureVisible(chips.last);
    await tester.tap(chips.last);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(chips.last).selected, isTrue);

    // Transaksi baru tiga bulan setelah data terbaru menggeser rentang chip.
    final latest = state.transactions.first.date;
    await state.addTransaction(
      TransactionModel(
        id: state.generateId(),
        category: 'Gaji',
        description: 'Gaji bulan depan',
        amount: 1000000,
        isIncome: true,
        date: DateTime(latest.year, latest.month + 3, 1),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, oldestLabel), findsNothing);
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .map((chip) => (chip.label as Text).data)
        .toList();
    expect(selected, ['Semua']);
  });
}
