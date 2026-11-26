import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/repositories/transaction_repository.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID', null));

  Future<({MemoryTransactions transactions, MemoryProfiles profiles})> openApp(
    WidgetTester tester,
    String tab,
  ) async {
    final state = AppState.instance..clearSession();
    final profiles = MemoryProfiles();
    final transactions = MemoryTransactions();
    transactions.rows['A'] = [
      TransactionMapper.fromMap('a', {
        'category': 'Gaji',
        'description': 'Awal',
        'amount': 10,
        'isIncome': true,
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'dateVersion': 2,
        'createdAt': Timestamp(100000, 0),
        'updatedAt': Timestamp(100000, 0),
        'revision': 1,
      }),
    ];
    state.useProfileRepository(profiles);
    state.useTransactionRepository(transactions);
    final auth = SessionAuth(
      currentUser: const SessionUser('A', 'a@example.com'),
    );
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.clearSession();
      tester.view.reset();
      await auth.events.close();
    });
    await tester.pumpWidget(SimanjaApp(initialRoute: '/home', auth: auth));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(tab),
      ),
    );
    await tester.pumpAndSettle();
    return (transactions: transactions, profiles: profiles);
  }

  testWidgets(
    'form transaksi mempertahankan draft dan tidak menutup saat conflict',
    (tester) async {
      final repositories = await openApp(tester, 'Transaksi');
      repositories.transactions.writeFailure = const RecordConflict(
        ConflictReason.changed,
      );
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Keterangan',
      );
      await tester.enterText(input, 'Draft belum disimpan');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final save = find.widgetWithText(ElevatedButton, 'Simpan Perubahan');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Draft belum disimpan',
      );
      expect(
        find.textContaining('Data sudah berubah di perangkat lain'),
        findsOneWidget,
      );
      expect(find.text('Transaksi diperbarui'), findsNothing);
      expect(AppState.instance.transactions.single.description, 'Awal');
    },
  );

  testWidgets('profil conflict mempertahankan isian, bukan sukses palsu', (
    tester,
  ) async {
    final repositories = await openApp(tester, 'Profil');
    repositories.profiles.profiles['A'] = repositories.profiles.profiles['A']!
        .copyWith(name: 'Nama B');
    final input = find.byKey(const Key('profile-name'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'Draft A');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('profile-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Data sudah berubah di perangkat lain'),
      findsOneWidget,
    );
    expect(find.text('Profil berhasil disimpan ke akun.'), findsNothing);
    expect(
      find.descendant(of: input, matching: find.text('Draft A')),
      findsOneWidget,
    );
    expect(repositories.profiles.profiles['A']!.name, 'Nama B');
  });

  testWidgets(
    'save profil berikutnya tidak menimpa field cloud yang tidak pernah diedit',
    (tester) async {
      final repositories = await openApp(tester, 'Profil');
      repositories.profiles.profiles['A'] = repositories.profiles.profiles['A']!
          .copyWith(city: 'Jakarta');
      final input = find.byKey(const Key('profile-name'));
      final save = find.byKey(const Key('profile-save'));
      for (final name in ['Nama pertama', 'Nama kedua']) {
        await tester.ensureVisible(input);
        await tester.enterText(input, name);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repositories.profiles.profiles['A']!.city, 'Jakarta');
        expect(repositories.profiles.profiles['A']!.name, name);
      }
    },
  );
}
