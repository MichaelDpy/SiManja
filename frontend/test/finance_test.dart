import 'package:flutter_test/flutter_test.dart';

import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/mock_data.dart';
import 'package:simanja/core/finance_summary.dart';

// ── Fixture helpers ───────────────────────────────────────────────────────

/// Buat TransactionModel minimal untuk tes.
TransactionModel _tx({
  required String id,
  required double amount,
  required bool isIncome,
  required DateTime date,
  String category = 'Gaji',
}) {
  return TransactionModel(
    id: id,
    category: category,
    description: 'Tes $id',
    amount: amount,
    isIncome: isIncome,
    date: date,
  );
}

void main() {
  // ── TransactionModel.validate ───────────────────────────────────────────
  group('TransactionModel.validate', () {
    test('lolos untuk bilangan bulat positif', () {
      expect(() => TransactionModel.validate(100000), returnsNormally);
      expect(() => TransactionModel.validate(1), returnsNormally);
    });

    test('gagal untuk nol', () {
      expect(() => TransactionModel.validate(0), throwsA(isA<ArgumentError>()));
    });

    test('gagal untuk negatif', () {
      expect(
        () => TransactionModel.validate(-500),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('gagal untuk pecahan desimal', () {
      expect(
        () => TransactionModel.validate(100.5),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('gagal untuk NaN', () {
      expect(
        () => TransactionModel.validate(double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('gagal untuk infinity', () {
      expect(
        () => TransactionModel.validate(double.infinity),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── FinanceSummary.totalIncome / totalExpense ───────────────────────────
  group('FinanceSummary agregasi', () {
    final ref = DateTime(2026, 11, 15);

    test('totalIncome = 0 saat daftar kosong', () {
      expect(FinanceSummary.totalIncome([]), 0.0);
    });

    test('totalExpense = 0 saat daftar kosong', () {
      expect(FinanceSummary.totalExpense([]), 0.0);
    });

    test('totalIncome hanya menjumlah isIncome=true', () {
      final txs = [
        _tx(id: '1', amount: 5_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 1_000_000, isIncome: false, date: ref),
        _tx(id: '3', amount: 3_000_000, isIncome: true, date: ref),
      ];
      expect(FinanceSummary.totalIncome(txs), 8_000_000.0);
    });

    test('totalExpense hanya menjumlah isIncome=false', () {
      final txs = [
        _tx(id: '1', amount: 5_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 1_200_000, isIncome: false, date: ref),
        _tx(id: '3', amount: 800_000, isIncome: false, date: ref),
      ];
      expect(FinanceSummary.totalExpense(txs), 2_000_000.0);
    });

    test('netCashFlow positif saat pemasukan > pengeluaran', () {
      final txs = [
        _tx(id: '1', amount: 8_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 3_000_000, isIncome: false, date: ref),
      ];
      expect(FinanceSummary.netCashFlow(txs), 5_000_000.0);
    });

    test('netCashFlow negatif saat pengeluaran > pemasukan', () {
      final txs = [
        _tx(id: '1', amount: 2_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 5_000_000, isIncome: false, date: ref),
      ];
      expect(FinanceSummary.netCashFlow(txs), -3_000_000.0);
    });
  });

  // ── FinanceSummary.savingsRate ──────────────────────────────────────────
  group('FinanceSummary.savingsRate', () {
    final ref = DateTime(2026, 11, 15);

    test('kembalikan null saat pemasukan nol (hanya ada pengeluaran)', () {
      final txs = [_tx(id: '1', amount: 500_000, isIncome: false, date: ref)];
      expect(FinanceSummary.savingsRate(txs), isNull);
    });

    test('kembalikan null saat daftar kosong', () {
      expect(FinanceSummary.savingsRate([]), isNull);
    });

    test('50% saat pengeluaran = setengah pemasukan', () {
      final txs = [
        _tx(id: '1', amount: 10_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 5_000_000, isIncome: false, date: ref),
      ];
      expect(FinanceSummary.savingsRate(txs), closeTo(50.0, 0.001));
    });

    test('negatif sah saat pengeluaran > pemasukan', () {
      final txs = [
        _tx(id: '1', amount: 2_000_000, isIncome: true, date: ref),
        _tx(id: '2', amount: 5_000_000, isIncome: false, date: ref),
      ];
      // (2jt - 5jt) / 2jt * 100 = -150%
      expect(FinanceSummary.savingsRate(txs), closeTo(-150.0, 0.001));
    });
  });

  // ── FinanceSummary.filterPeriod / filterMonth ───────────────────────────
  group('FinanceSummary filter periode', () {
    final txs = [
      _tx(id: 'a', amount: 1000, isIncome: true, date: DateTime(2025, 12, 31)),
      _tx(id: 'b', amount: 1000, isIncome: true, date: DateTime(2026, 1, 1)),
      _tx(id: 'c', amount: 1000, isIncome: true, date: DateTime(2026, 1, 31)),
      _tx(id: 'd', amount: 1000, isIncome: true, date: DateTime(2026, 2, 1)),
      _tx(id: 'e', amount: 1000, isIncome: true, date: DateTime(2026, 2, 28)),
    ];

    test('filterMonth Jan 2026 tepat [1 Jan, 1 Feb)', () {
      final result = FinanceSummary.filterMonth(txs, year: 2026, month: 1);
      expect(result.map((t) => t.id).toList(), ['b', 'c']);
    });

    test('filterMonth Des 2025 — transaksi 31 Des masuk', () {
      final result = FinanceSummary.filterMonth(txs, year: 2025, month: 12);
      expect(result.map((t) => t.id).toList(), ['a']);
    });

    test('filterMonth Feb 2026 masukkan tanggal 28', () {
      final result = FinanceSummary.filterMonth(txs, year: 2026, month: 2);
      expect(result.map((t) => t.id).toList(), ['d', 'e']);
    });

    test('filterPeriod eksklusif pada until', () {
      final result = FinanceSummary.filterPeriod(
        txs,
        from: DateTime(2026, 1, 1),
        until: DateTime(2026, 2, 1),
      );
      expect(result.map((t) => t.id).toList(), ['b', 'c']);
    });
  });

  // ── FinanceSummary.sorted ───────────────────────────────────────────────
  group('FinanceSummary.sorted', () {
    test('tanggal terbaru dulu; ID ascending saat tanggal sama', () {
      final txs = [
        _tx(id: 'C', amount: 1000, isIncome: true, date: DateTime(2026, 11, 1)),
        _tx(id: 'A', amount: 1000, isIncome: true, date: DateTime(2026, 11, 3)),
        _tx(id: 'B', amount: 1000, isIncome: true, date: DateTime(2026, 11, 3)),
        _tx(id: 'D', amount: 1000, isIncome: true, date: DateTime(2026, 10, 1)),
      ];
      final sorted = FinanceSummary.sorted(txs);
      expect(sorted.map((t) => t.id).toList(), ['A', 'B', 'C', 'D']);
    });

    test('tidak memodifikasi daftar asli', () {
      final original = [
        _tx(id: 'Z', amount: 1000, isIncome: true, date: DateTime(2026, 1, 1)),
        _tx(id: 'A', amount: 1000, isIncome: true, date: DateTime(2026, 6, 1)),
      ];
      FinanceSummary.sorted(original);
      expect(original.first.id, 'Z');
    });
  });

  // ── FinanceSummary.monthlySeries ────────────────────────────────────────
  group('FinanceSummary.monthlySeries', () {
    final anchor = MockData.demoAnchor; // Nov 2026

    test('menghasilkan tepat monthCount entri', () {
      final series = FinanceSummary.monthlySeries(
        MockData.transactions,
        monthCount: 6,
        referenceMonth: anchor,
      );
      expect(series.length, 6);
    });

    test('entri pertama = Jun 2026 (6 bulan sebelum Nov)', () {
      final series = FinanceSummary.monthlySeries(
        MockData.transactions,
        monthCount: 6,
        referenceMonth: anchor,
      );
      expect(series.first.month, 6);
      expect(series.first.year, 2026);
    });

    test('entri terakhir = Nov 2026 (anchor)', () {
      final series = FinanceSummary.monthlySeries(
        MockData.transactions,
        monthCount: 6,
        referenceMonth: anchor,
      );
      expect(series.last.month, 11);
      expect(series.last.year, 2026);
    });

    test('Agu 2026 (kosong di fixture) muncul dengan income=0 expense=0', () {
      final series = FinanceSummary.monthlySeries(
        MockData.transactions,
        monthCount: 6,
        referenceMonth: anchor,
      );
      // indeks 2 = Agu (Jun=0, Jul=1, Agu=2)
      final aug = series[2];
      expect(aug.month, 8);
      expect(aug.income, 0.0);
      expect(aug.expense, 0.0);
    });

    test('wrap tahun: Feb 2026, 3 bulan → Des 2025, Jan 2026, Feb 2026', () {
      final txs = [
        _tx(
          id: '1',
          amount: 5000,
          isIncome: true,
          date: DateTime(2025, 12, 15),
        ),
        _tx(id: '2', amount: 3000, isIncome: true, date: DateTime(2026, 1, 10)),
        _tx(id: '3', amount: 2000, isIncome: true, date: DateTime(2026, 2, 5)),
      ];
      final series = FinanceSummary.monthlySeries(
        txs,
        monthCount: 3,
        referenceMonth: DateTime(2026, 2),
      );
      expect(series.map((s) => '${s.year}-${s.month}').toList(), [
        '2025-12',
        '2026-1',
        '2026-2',
      ]);
      expect(series[0].income, 5000.0);
      expect(series[1].income, 3000.0);
      expect(series[2].income, 2000.0);
    });

    test('MonthlySummary.shortLabel benar untuk semua 12 bulan', () {
      final labels = List.generate(12, (i) {
        return MonthlySummary(
          year: 2026,
          month: i + 1,
          income: 0,
          expense: 0,
        ).shortLabel;
      });
      expect(labels, [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Ags',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ]);
    });
  });

  // ── FinanceSummary.expenseByCategory ───────────────────────────────────
  group('FinanceSummary.expenseByCategory', () {
    final ref = DateTime(2026, 11, 1);

    test('map kosong saat tidak ada pengeluaran', () {
      final txs = [_tx(id: '1', amount: 5_000_000, isIncome: true, date: ref)];
      expect(FinanceSummary.expenseByCategory(txs), isEmpty);
    });

    test('menjumlah per kategori dan urut terbesar dulu', () {
      final txs = [
        _tx(
          id: '1',
          amount: 500_000,
          isIncome: false,
          date: ref,
          category: 'Tagihan',
        ),
        _tx(
          id: '2',
          amount: 300_000,
          isIncome: false,
          date: ref,
          category: 'Makan & Minum',
        ),
        _tx(
          id: '3',
          amount: 700_000,
          isIncome: false,
          date: ref,
          category: 'Tagihan',
        ),
      ];
      final result = FinanceSummary.expenseByCategory(txs);
      expect(result.keys.first, 'Tagihan');
      expect(result['Tagihan'], 1_200_000.0);
      expect(result['Makan & Minum'], 300_000.0);
    });
  });

  // ── AppState mutasi via ID ──────────────────────────────────────────────
  group('AppState mutasi via ID', () {
    setUp(() => AppState.instance.reset());

    test('addTransaction menambah ke daftar', () async {
      final before = AppState.instance.transactions.length;
      await AppState.instance.addTransaction(
        _tx(
          id: 'NEW01',
          amount: 500_000,
          isIncome: true,
          date: DateTime(2026, 11, 20),
        ),
      );
      expect(AppState.instance.transactions.length, before + 1);
      expect(
        AppState.instance.transactions.any((t) => t.id == 'NEW01'),
        isTrue,
      );
    });

    test('addTransaction menolak amount 0', () async {
      await expectLater(
        () => AppState.instance.addTransaction(
          _tx(
            id: 'BAD',
            amount: 0,
            isIncome: true,
            date: DateTime(2026, 11, 1),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('addTransaction menolak amount pecahan', () async {
      await expectLater(
        () => AppState.instance.addTransaction(
          _tx(
            id: 'BAD2',
            amount: 1500.75,
            isIncome: false,
            date: DateTime(2026, 11, 1),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('updateTransaction via ID stabil mengubah deskripsi', () async {
      final original = AppState.instance.transactions.firstWhere(
        (t) => t.id == 'TRX001',
      );
      final updated = original.copyWith(description: 'Gaji Diperbarui');
      await AppState.instance.updateTransaction('TRX001', updated);
      final found = AppState.instance.transactions.firstWhere(
        (t) => t.id == 'TRX001',
      );
      expect(found.description, 'Gaji Diperbarui');
    });

    test('updateTransaction ID tidak ada melempar ArgumentError', () async {
      await expectLater(
        () => AppState.instance.updateTransaction(
          'TIDAK_ADA',
          _tx(
            id: 'TIDAK_ADA',
            amount: 100_000,
            isIncome: true,
            date: DateTime(2026, 11, 1),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteTransaction menghapus dari daftar', () async {
      expect(
        AppState.instance.transactions.any((t) => t.id == 'TRX001'),
        isTrue,
      );
      await AppState.instance.deleteTransaction('TRX001');
      expect(
        AppState.instance.transactions.any((t) => t.id == 'TRX001'),
        isFalse,
      );
    });

    test('deleteTransaction idempoten untuk ID tidak ada', () async {
      final before = AppState.instance.transactions.length;
      await AppState.instance.deleteTransaction('ID_TIDAK_ADA');
      expect(AppState.instance.transactions.length, before);
    });

    test(
      'hapus transaksi pemasukan tidak mengubah jumlah pengeluaran',
      () async {
        final income = AppState.instance.transactions.firstWhere(
          (t) => t.isIncome,
        );
        final expenseBefore = AppState.instance.transactions
            .where((t) => !t.isIncome)
            .length;
        await AppState.instance.deleteTransaction(income.id);
        final expenseAfter = AppState.instance.transactions
            .where((t) => !t.isIncome)
            .length;
        expect(expenseAfter, expenseBefore);
      },
    );

    test(
      'transactions selalu diurutkan tanggal terbaru dulu setelah add',
      () async {
        await AppState.instance.addTransaction(
          _tx(
            id: 'OLD',
            amount: 100_000,
            isIncome: true,
            date: DateTime(2024, 1, 1),
          ),
        );
        await AppState.instance.addTransaction(
          _tx(
            id: 'FUTURE',
            amount: 100_000,
            isIncome: true,
            date: DateTime(2027, 1, 1),
          ),
        );
        final txs = AppState.instance.transactions;
        final idxNew = txs.indexWhere((t) => t.id == 'FUTURE');
        final idxOld = txs.indexWhere((t) => t.id == 'OLD');
        expect(idxNew, lessThan(idxOld));
      },
    );

    test('transactions adalah unmodifiable list', () {
      final list = AppState.instance.transactions;
      expect(
        () => (list as dynamic).add(
          _tx(
            id: 'X',
            amount: 1000,
            isIncome: true,
            date: DateTime(2026, 11, 1),
          ),
        ),
        throwsA(anything),
      );
    });
  });

  // ── MockData fixture ────────────────────────────────────────────────────
  group('MockData fixture', () {
    test('dummyUser tersedia dan email mengandung "demo"', () {
      expect(MockData.dummyUser.email, contains('demo'));
      expect(MockData.dummyUser.name, isNotEmpty);
    });

    test('demoAnchor adalah Nov 2026', () {
      expect(MockData.demoAnchor.year, 2026);
      expect(MockData.demoAnchor.month, 11);
    });

    test('semua transaksi tidak melebihi bulan anchor', () {
      final anchor = MockData.demoAnchor;
      for (final t in MockData.transactions) {
        expect(
          t.date.isBefore(DateTime(anchor.year, anchor.month + 1)),
          isTrue,
          reason: 'Transaksi ${t.id} melanggar batas anchor',
        );
      }
    });

    test('tidak ada amount <= 0 atau pecahan di fixture', () {
      for (final t in MockData.transactions) {
        expect(t.amount > 0, isTrue, reason: '${t.id} amount tidak positif');
        expect(
          t.amount,
          t.amount.roundToDouble(),
          reason: '${t.id} amount bukan bilangan bulat',
        );
      }
    });

    test('semua ID transaksi unik', () {
      final ids = MockData.transactions.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
