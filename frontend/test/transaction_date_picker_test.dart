import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

void main() {
  final state = AppState.instance;
  late MemoryTransactions repository;
  late SessionAuth auth;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  setUp(() {
    state.clearSession();
    repository = MemoryTransactions();
    state.useTransactionRepository(repository);
    state.useProfileRepository(MemoryProfiles());
    auth = SessionAuth(currentUser: const SessionUser('A', 'a@example.com'));
  });

  Future<void> openForm(WidgetTester tester, {bool edit = false}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
      await auth.events.close();
    });
    // Gunakan konfigurasi aplikasi asli, tanpa delegates tambahan dari harness.
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Transaksi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      edit
          ? find.byIcon(Icons.edit_outlined).first
          : find.byTooltip('Tambah Transaksi'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCalendar(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final calendar = find.byIcon(Icons.calendar_today_outlined);
    await tester.ensureVisible(calendar);
    await tester.tap(calendar);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets('edit keterangan legacy mempertahankan timestamp tanggal asli', (
    tester,
  ) async {
    final original = Timestamp.fromDate(
      DateTime.parse('2026-11-26T00:00:00+07:00'),
    );
    repository.rows['A'] = [
      TransactionMapper.fromMap('legacy', {
        'category': 'Gaji',
        'description': 'Transaksi lama',
        'amount': 12000,
        'isIncome': true,
        'date': original,
        'createdAt': Timestamp(1234567890, 0),
        'updatedAt': Timestamp(1234567900, 0),
      }),
    ];
    await openForm(tester, edit: true);
    await tester.enterText(input('Keterangan'), 'Keterangan diperbarui');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.widgetWithText(ElevatedButton, 'Simpan Perubahan');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final saved = repository.rows['A']!.single;
    expect(saved.description, 'Keterangan diperbarui');
    expect(saved.needsDateReview, isTrue);
    expect(TransactionMapper.toMap(saved)['date'], original);
    expect(TransactionMapper.toMap(saved).containsKey('dateVersion'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'kalender transaksi terbuka dalam bahasa Indonesia dan bisa batal',
    (tester) async {
      await openForm(tester);
      final calendarDate = find
          .ancestor(
            of: find.byIcon(Icons.calendar_today_outlined),
            matching: find.byType(InkWell),
          )
          .first;
      final originalText = tester
          .widgetList<Text>(
            find.descendant(of: calendarDate, matching: find.byType(Text)),
          )
          .map((widget) => widget.data)
          .whereType<String>()
          .single;
      await openCalendar(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final context = tester.element(find.byType(DatePickerDialog));
      expect(Localizations.localeOf(context), const Locale('id', 'ID'));
      final labels = MaterialLocalizations.of(context);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.toLowerCase() ==
                  labels.cancelButtonLabel.toLowerCase(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.text(originalText), findsOneWidget);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tanggal kabisat yang dipilih tersimpan pada transaksi baru', (
    tester,
  ) async {
    await openForm(tester);
    await tester.tap(find.byType(DropdownButton<CategoryMeta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaji').last);
    await tester.pumpAndSettle();
    await tester.enterText(input('Keterangan'), 'Transaksi tanggal kabisat');
    await tester.enterText(input('Jumlah (Rp)'), '12000');
    await openCalendar(tester);
    final context = tester.element(find.byType(DatePickerDialog));
    final labels = MaterialLocalizations.of(context);
    await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    final dateInput = find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    );
    final leapDay = DateTime(2024, 2, 29);
    await tester.enterText(dateInput, labels.formatCompactDate(leapDay));
    await tester.tap(find.text(labels.okButtonLabel));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(
      find.text(DateFormat('d MMMM yyyy', 'id_ID').format(leapDay)),
      findsOneWidget,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Tambah Transaksi'));
    await tester.pumpAndSettle();
    final saved = repository.rows['A']!.single;
    expect(saved.date, leapDay);
    expect(saved.amount, 12000);
    expect(saved.category, 'Gaji');
    expect(saved.isIncome, isTrue);
    expect(tester.takeException(), isNull);
  });
}
