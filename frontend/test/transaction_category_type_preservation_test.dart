// A1-02 — Regresi widget: pertahankan kategori dan jenis transaksi lama
//
// Menutup audit A02.
//
// Kriteria lulus:
//   - Edit Biaya Khusus/isIncome=false mempertahankan kategori/jenis/ID/nominal.
//   - Kategori tak dikenal tetap dapat disimpan jika tidak diubah sengaja.
//   - Kategori dikenal dengan jenis legacy tidak selaras tetap utuh.
//   - Tidak menurunkan ulang jenis dari kategori ketika hanya keterangan berubah.
//   - Perubahan kategori/jenis eksplisit diterapkan.
//   - Edit daftar tersaring (Pemasukan/Pengeluaran) tepat target.
//   - Pemeriksaan payload mutasi repository (TransactionMapper.toMap).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/main.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

import 'support/memory_profiles.dart';
import 'support/memory_transactions.dart';
import 'support/session_auth.dart';

// ── Helpers ─────────────────────────────────────────────────────────────────

Finder _input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _click(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Spy repository: rekam payload mutasi `update` & `add` apa adanya.
class _SpyTransactions extends MemoryTransactions {
  final updates = <({String uid, String id, TransactionModel transaction})>[];
  final adds = <TransactionModel>[];

  @override
  Future<void> update(
    String uid,
    String id,
    TransactionModel transaction,
  ) async {
    updates.add((uid: uid, id: id, transaction: transaction));
    await super.update(uid, id, transaction);
  }

  @override
  Future<void> add(String uid, TransactionModel transaction) async {
    adds.add(transaction);
    await super.add(uid, transaction);
  }
}

/// Boot app ke layar transaksi dengan akun siap; kembalikan spy repository.
Future<_SpyTransactions> _boot(WidgetTester tester, SessionAuth auth) async {
  final profiles = MemoryProfiles();
  final transactions = _SpyTransactions();
  final state = AppState.instance..clearSession();
  state.useProfileRepository(profiles);
  state.useTransactionRepository(transactions);
  await tester.pumpWidget(SimanjaApp(initialRoute: '/login', auth: auth));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-email')), 'a@example.com');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'Password-uji123!',
  );
  await _click(tester, find.byKey(const Key('login-submit')));
  await _click(
    tester,
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.text('Transaksi'),
    ),
  );
  return transactions;
}

TransactionModel _tx({
  required String id,
  required String category,
  required bool isIncome,
  required double amount,
  required String description,
  DateTime? date,
}) => TransactionModel(
  id: id,
  category: category,
  description: description,
  amount: amount,
  isIncome: isIncome,
  date: date ?? DateTime(2026, 1, 15),
);

/// Seed data transaksi ke sesi & buka sheet edit untuk [description].
Future<void> _seedAndOpenEdit(
  WidgetTester tester,
  _SpyTransactions transactions,
  List<TransactionModel> seed,
  String description, {
  String? filteredTab,
}) async {
  final uid = AppState.instance.sessionUid!;
  transactions.emit(uid, seed);
  await tester.pumpAndSettle();
  if (filteredTab != null) {
    await _click(
      tester,
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text(filteredTab),
      ),
    );
  }
  await _click(tester, find.bySemanticsLabel('Edit transaksi $description'));
}

/// Ubah hanya keterangan lalu simpan; kembalikan payload mutasi `update`.
Future<({String uid, String id, TransactionModel transaction})> _editOnlyNote(
  WidgetTester tester,
  _SpyTransactions transactions, {
  required String newNote,
}) async {
  await tester.enterText(_input('Keterangan'), newNote);
  await tester.pumpAndSettle();
  await _click(tester, find.text('Simpan Perubahan'));
  expect(
    find.text('Pilih kategori terlebih dahulu'),
    findsNothing,
    reason: 'kategori asal tidak boleh memblokir penyimpanan',
  );
  expect(
    transactions.updates,
    hasLength(1),
    reason: 'tepat satu mutasi update',
  );
  return transactions.updates.single;
}

/// Payload Firestore efektif (TransactionMapper.toMap) dari transaksi.
Map<String, Object> _payload(TransactionModel tx) =>
    TransactionMapper.toMap(tx);

void _expectPreserved(
  ({String uid, String id, TransactionModel transaction}) update, {
  required String id,
  required String category,
  required bool isIncome,
  required num amount,
}) {
  final tx = update.transaction;
  // Model yang dikirim ke repository.
  expect(update.id, id, reason: 'target id tidak boleh berubah');
  expect(tx.id, id, reason: 'id transaksi dipertahankan');
  expect(update.id, tx.id);
  expect(tx.category, category, reason: 'kategori dipertahankan');
  expect(tx.isIncome, isIncome, reason: 'jenis tidak diturunkan ulang');
  expect(tx.amount, amount, reason: 'nominal dipertahankan');

  // Payload mutasi efektif (Firestore).
  final payload = _payload(tx);
  expect(payload['category'], category);
  expect(payload['isIncome'], isIncome);
  expect(payload['amount'], amount);
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('id_ID', null);
  });

  Future<SessionAuth> scaffold(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = SessionAuth();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      AppState.instance.clearSession();
      await auth.events.close();
    });
    return auth;
  }

  // ── 1. Kategori tak dikenal + jenis lama ──────────────────────────────

  group('A1-02 — kategori tak dikenal', () {
    testWidgets('Edit Biaya Khusus/isIncome=false hanya ubah keterangan: '
        'kategori/jenis/ID/nominal utuh (payload mutasi diperiksa)', (
      tester,
    ) async {
      final auth = await scaffold(tester);
      final transactions = await _boot(tester, auth);

      await _seedAndOpenEdit(tester, transactions, [
        _tx(
          id: 'tx-biaya-khusus',
          category: 'Biaya Khusus', // tidak ada di knownCategories
          isIncome: false,
          amount: 50000,
          description: 'Biaya lama',
        ),
      ], 'Biaya lama');

      // Hint kategori tak dikenal tampil, tidak di-fallback diam-diam.
      expect(find.textContaining('tidak dikenal'), findsOneWidget);
      expect(find.textContaining('Biaya Khusus'), findsWidgets);

      final update = await _editOnlyNote(
        tester,
        transactions,
        newNote: 'Biaya khusus diperbarui',
      );

      _expectPreserved(
        update,
        id: 'tx-biaya-khusus',
        category: 'Biaya Khusus',
        isIncome: false,
        amount: 50000,
      );
      // Keterangan memang berubah; sisanya tidak.
      expect(update.transaction.description, 'Biaya khusus diperbarui');
      expect(
        _payload(update.transaction)['description'],
        'Biaya khusus diperbarui',
      );
      expect(update.transaction.date, DateTime(2026, 1, 15));
    });

    testWidgets('kategori tak dikenal + jenis pemasukan lama tetap utuh saat '
        'hanya keterangan berubah', (tester) async {
      final auth = await scaffold(tester);
      final transactions = await _boot(tester, auth);

      await _seedAndOpenEdit(tester, transactions, [
        _tx(
          id: 'tx-unknown-income',
          category: 'Kategori Lama Langka',
          isIncome: true,
          amount: 750000,
          description: 'Masuk lama',
        ),
      ], 'Masuk lama');

      final update = await _editOnlyNote(
        tester,
        transactions,
        newNote: 'Masuk lama direvisi',
      );

      _expectPreserved(
        update,
        id: 'tx-unknown-income',
        category: 'Kategori Lama Langka',
        isIncome: true,
        amount: 750000,
      );
    });
  });

  // ── 2. Kategori dikenal dengan jenis legacy tidak selaras ──────────────

  group('A1-02 — kategori dikenal + jenis legacy tidak selaras', () {
    testWidgets(
      'kategori dikenal (pemasukan) tapi isIncome=false lama tetap utuh '
      'saat hanya keterangan berubah',
      (tester) async {
        final auth = await scaffold(tester);
        final transactions = await _boot(tester, auth);

        // 'Gaji' dikenal sebagai pemasukan, tapi data lama menyimpan false.
        await _seedAndOpenEdit(tester, transactions, [
          _tx(
            id: 'tx-gaji-mismatch',
            category: 'Gaji',
            isIncome: false,
            amount: 3000000,
            description: 'Gaji anomali',
          ),
        ], 'Gaji anomali');

        final update = await _editOnlyNote(
          tester,
          transactions,
          newNote: 'Gaji anomali revisi',
        );

        _expectPreserved(
          update,
          id: 'tx-gaji-mismatch',
          category: 'Gaji',
          isIncome: false, // TIDAK diturunkan ulang jadi true dari kategori
          amount: 3000000,
        );
      },
    );

    testWidgets(
      'kategori dikenal (pengeluaran) tapi isIncome=true lama tetap utuh '
      'saat hanya keterangan berubah',
      (tester) async {
        final auth = await scaffold(tester);
        final transactions = await _boot(tester, auth);

        // 'Makan & Minum' dikenal sebagai pengeluaran, tapi data lama true.
        await _seedAndOpenEdit(tester, transactions, [
          _tx(
            id: 'tx-makan-mismatch',
            category: 'Makan & Minum',
            isIncome: true,
            amount: 45000,
            description: 'Makan anomali',
          ),
        ], 'Makan anomali');

        final update = await _editOnlyNote(
          tester,
          transactions,
          newNote: 'Makan anomali revisi',
        );

        _expectPreserved(
          update,
          id: 'tx-makan-mismatch',
          category: 'Makan & Minum',
          isIncome: true, // TIDAK diturunkan ulang jadi false dari kategori
          amount: 45000,
        );
      },
    );
  });

  // ── 3. Perubahan kategori/jenis eksplisit ─────────────────────────────

  group('A1-02 — perubahan kategori/jenis eksplisit', () {
    testWidgets('ganti kategori eksplisit ke kategori lain (jenis sama): '
        'kategori baru diterapkan, ID & nominal utuh', (tester) async {
      final auth = await scaffold(tester);
      final transactions = await _boot(tester, auth);

      await _seedAndOpenEdit(tester, transactions, [
        _tx(
          id: 'tx-explicit-cat',
          category: 'Makan & Minum',
          isIncome: false,
          amount: 20000,
          description: 'Belanja X',
        ),
      ], 'Belanja X');

      await _click(tester, find.byType(DropdownButton<CategoryMeta>));
      await _click(tester, find.text('Transportasi').last);
      await _click(tester, find.text('Simpan Perubahan'));

      expect(transactions.updates, hasLength(1));
      final update = transactions.updates.single;
      expect(update.id, 'tx-explicit-cat');
      expect(update.transaction.id, 'tx-explicit-cat');
      expect(update.transaction.category, 'Transportasi');
      expect(update.transaction.isIncome, isFalse);
      expect(update.transaction.amount, 20000);
      expect(update.transaction.description, 'Belanja X');

      final payload = _payload(update.transaction);
      expect(payload['category'], 'Transportasi');
      expect(payload['isIncome'], false);
      expect(payload['amount'], 20000);
    });

    testWidgets(
      'ganti jenis eksplisit lewat kategori grup lawan: isIncome ikut '
      'pilihan baru, kategori & ID & nominal tepat',
      (tester) async {
        final auth = await scaffold(tester);
        final transactions = await _boot(tester, auth);

        await _seedAndOpenEdit(tester, transactions, [
          _tx(
            id: 'tx-explicit-type',
            category: 'Makan & Minum',
            isIncome: false,
            amount: 80000,
            description: 'Tukar jenis',
          ),
        ], 'Tukar jenis');

        await _click(tester, find.byType(DropdownButton<CategoryMeta>));
        await _click(tester, find.text('Gaji').last); // grup pemasukan
        await _click(tester, find.text('Simpan Perubahan'));

        expect(transactions.updates, hasLength(1));
        final update = transactions.updates.single;
        expect(update.id, 'tx-explicit-type');
        expect(update.transaction.category, 'Gaji');
        expect(update.transaction.isIncome, isTrue);
        expect(update.transaction.amount, 80000);
        expect(_payload(update.transaction)['isIncome'], true);
      },
    );

    testWidgets('kategori tak dikenal + pilih kategori eksplisit: pilihan baru '
        'menggantikan kategori asal', (tester) async {
      final auth = await scaffold(tester);
      final transactions = await _boot(tester, auth);

      await _seedAndOpenEdit(tester, transactions, [
        _tx(
          id: 'tx-unknown-then-pick',
          category: 'Biaya Khusus',
          isIncome: false,
          amount: 15000,
          description: 'Normalisasi kategori',
        ),
      ], 'Normalisasi kategori');

      await _click(tester, find.byType(DropdownButton<CategoryMeta>));
      await _click(tester, find.text('Tagihan').last);
      await _click(tester, find.text('Simpan Perubahan'));

      expect(transactions.updates, hasLength(1));
      final update = transactions.updates.single;
      expect(update.id, 'tx-unknown-then-pick');
      expect(update.transaction.category, 'Tagihan');
      expect(update.transaction.isIncome, isFalse);
      expect(update.transaction.amount, 15000);
    });
  });

  // ── 4. Edit daftar tersaring tepat target ─────────────────────────────

  group('A1-02 — edit daftar tersaring tepat target', () {
    testWidgets('edit dari tab Pengeluaran tepat menarget transaksi itu; '
        'transaksi lain tidak disentuh', (tester) async {
      final auth = await scaffold(tester);
      final transactions = await _boot(tester, auth);

      final income = _tx(
        id: 'tx-income',
        category: 'Gaji',
        isIncome: true,
        amount: 4000000,
        description: 'Gaji bulanan',
      );
      final expense = _tx(
        id: 'tx-expense',
        category: 'Biaya Khusus',
        isIncome: false,
        amount: 25000,
        description: 'Biaya operasional',
      );

      // Kategori tak dikenal + jenis lama → tampil di tab Pengeluaran.
      await _seedAndOpenEdit(
        tester,
        transactions,
        [income, expense],
        'Biaya operasional',
        filteredTab: 'Pengeluaran',
      );

      // Hanya transaksi target terlihat di daftar tersaring.
      expect(find.text('Gaji bulanan'), findsNothing);

      final update = await _editOnlyNote(
        tester,
        transactions,
        newNote: 'Biaya operasional revisi',
      );

      _expectPreserved(
        update,
        id: 'tx-expense',
        category: 'Biaya Khusus',
        isIncome: false,
        amount: 25000,
      );

      // Transaksi lain tidak berubah di repository.
      final uid = update.uid;
      final rows = transactions.rows[uid]!;
      final incomeRow = rows.firstWhere((t) => t.id == 'tx-income');
      expect(incomeRow.description, 'Gaji bulanan');
      expect(incomeRow.category, 'Gaji');
      expect(incomeRow.isIncome, isTrue);
      expect(incomeRow.amount, 4000000);
      expect(transactions.updates.single.id, 'tx-expense');
    });

    testWidgets(
      'kategori dikenal + jenis legacy tidak selaras di daftar tersaring: '
      'edit tetap tepat target & jenis dipertahankan',
      (tester) async {
        final auth = await scaffold(tester);
        final transactions = await _boot(tester, auth);

        // 'Gaji' dikenal pemasukan tapi isIncome=false → tampil di Pengeluaran.
        final mismatched = _tx(
          id: 'tx-filtered-mismatch',
          category: 'Gaji',
          isIncome: false,
          amount: 100000,
          description: 'Gaji disaring',
        );
        final other = _tx(
          id: 'tx-filtered-other',
          category: 'Makan & Minum',
          isIncome: false,
          amount: 30000,
          description: 'Lainnya disaring',
        );

        await _seedAndOpenEdit(
          tester,
          transactions,
          [mismatched, other],
          'Gaji disaring',
          filteredTab: 'Pengeluaran',
        );

        final update = await _editOnlyNote(
          tester,
          transactions,
          newNote: 'Gaji disaring revisi',
        );

        _expectPreserved(
          update,
          id: 'tx-filtered-mismatch',
          category: 'Gaji',
          isIncome: false,
          amount: 100000,
        );
        expect(transactions.updates.single.id, 'tx-filtered-mismatch');
      },
    );
  });
}
