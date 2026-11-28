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

  // ── A1-09: state pending pada dismissal + no-duplicate / no stale feedback ──

  testWidgets(
    'state pending: Back/close/tap luar/swipe diblokir; tidak cancel RPC; tidak ada write ganda',
    (tester) async {
      final repository = await form(tester);
      repository.pendingWrite = Completer<void>();
      await submit(tester);
      await tester.pump();
      expect(AppState.instance.pendingMutations, 1);
      expect(tester.widget<TextField>(input('Keterangan')).enabled, isFalse);

      // Back
      await tester.binding.handlePopRoute();
      await tester.pump();
      // Close (dinonaktifkan saat pending)
      final close = tester.widget<IconButton>(
        find.byKey(const Key('close-transaction-form')),
      );
      expect(close.onPressed, isNull);
      // Tap luar
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      // Swipe-down
      await tester.fling(
        find.byKey(const Key('transaction-sheet-swipe-handle')),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();

      // Form tidak tertutup, tidak ada discard dialog, tidak ada sukses.
      expect(input('Keterangan'), findsOneWidget);
      expect(find.text('Buang perubahan?'), findsNothing);
      expect(find.text('Transaksi ditambahkan'), findsNothing);
      // Pesan pending eksplisit; TIDAK menjanjikan pembatalan RPC.
      expect(
        find.textContaining('permintaan belum dibatalkan'),
        findsOneWidget,
      );
      expect(find.textContaining('dibatalkan...'), findsNothing);
      // Tidak ada write ganda; masih satu mutasi pending.
      expect(AppState.instance.pendingMutations, 1);
      expect(repository.committedWrites, 0);

      repository.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(repository.committedWrites, 1);
      expect(find.text('Transaksi ditambahkan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UID switch saat pending: tidak ada write ganda atau feedback sesi lama',
    (tester) async {
      final repository = await form(tester);
      repository.pendingWrite = Completer<void>();
      await submit(tester);
      await tester.pump();
      expect(AppState.instance.pendingMutations, 1);

      // Ganti UID saat permintaan berjalan.
      await AppState.instance.clearSession();
      repository.pendingWrite!.complete();
      await tester.pumpAndSettle();

      // Satu permintaan saja; tidak ada write kedua untuk sesi baru.
      expect(repository.attemptedIds, hasLength(1));
      // Tidak ada feedback sesi lama: bukan sukses, bukan error form.
      expect(find.text('Transaksi ditambahkan'), findsNothing);
      expect(find.textContaining('Gagal menyimpan'), findsNothing);
      expect(find.text('Buang perubahan?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
