import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/services/auth_service.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID', null));
  Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<MemoryTransactions> form(WidgetTester tester) async {
    final state = AppState.instance..clearSession();
    final repository = MemoryTransactions();
    state.useTransactionRepository(repository);
    state.useProfileRepository(MemoryProfiles());
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
        matching: find.text('Transaksi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tambah Transaksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<CategoryMeta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaji').last);
    await tester.pumpAndSettle();
    await tester.enterText(input('Keterangan'), 'Transaksi tertunda');
    await tester.enterText(input('Jumlah (Rp)'), '100');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> submit(WidgetTester tester) async {
    final save = find.widgetWithText(ElevatedButton, 'Tambah Transaksi');
    await tester.ensureVisible(save);
    await tester.tap(save);
  }

  testWidgets(
    'lost ack mempertahankan form dan ID; retry tidak membuat transaksi kedua',
    (tester) async {
      final repository = await form(tester);
      repository.failureAfterCommit = TimeoutException('lost ack');
      await submit(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Hasil penyimpanan belum dapat dipastikan'),
        findsWidgets,
      );
      expect(find.text('Transaksi ditambahkan'), findsNothing);
      expect(
        tester.widget<TextField>(input('Keterangan')).controller!.text,
        'Transaksi tertunda',
      );
      expect(repository.rows['A'], hasLength(1));
      await submit(tester);
      await tester.pumpAndSettle();
      expect(repository.attemptedIds, hasLength(2));
      expect(repository.attemptedIds[0], repository.attemptedIds[1]);
      expect(repository.committedWrites, 1);
      expect(repository.rows['A'], hasLength(1));
      expect(find.text('Transaksi ditambahkan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'request berjalan mengunci form dan Back tidak dianggap cancel write',
    (tester) async {
      final repository = await form(tester);
      repository.pendingWrite = Completer<void>();
      await submit(tester);
      await tester.pump();
      expect(tester.widget<TextField>(input('Keterangan')).enabled, isFalse);
      expect(AppState.instance.pendingMutations, 1);
      expect(find.text('Transaksi ditambahkan'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.textContaining('permintaan belum dibatalkan'),
        findsOneWidget,
      );
      expect(input('Keterangan'), findsOneWidget);
      expect(repository.committedWrites, 0);
      repository.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(repository.committedWrites, 1);
      expect(find.text('Transaksi ditambahkan'), findsOneWidget);
    },
  );
}
