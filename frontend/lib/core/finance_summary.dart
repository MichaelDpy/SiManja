import 'rupiah.dart';
import 'calendar_date.dart';
import '../models/transaction_model.dart';

/// Utilitas laporan keuangan SIMANJA.
///
/// Semua fungsi murni (pure function) — tidak bergantung pada AppState,
/// sehingga dapat diuji secara terisolasi.
///
/// Konvensi batas bulan:
///   - awal periode = hari pertama bulan tersebut (inklusif)
///   - akhir periode = hari pertama bulan berikutnya (eksklusif)
///
/// Referensi: 00-panduan-tim.md § Kontrak antarmodul
abstract final class FinanceSummary {
  // ── Filter ──────────────────────────────────────────────────────────────

  /// Kembalikan transaksi yang tanggalnya jatuh dalam rentang [from, until).
  ///
  /// [from] inklusif dan [until] eksklusif, memakai komponen tanggal R-DATE.
  /// Jam dan flag UTC/lokal bukan batas instant pada laporan kalender.
  static List<TransactionModel> filterPeriod(
    List<TransactionModel> txList, {
    required DateTime from,
    required DateTime until,
  }) {
    final start = CalendarDate.canonical(from);
    final end = CalendarDate.canonical(until);
    return txList.where((t) {
      final day = CalendarDate.canonical(t.date);
      return !day.isBefore(start) && day.isBefore(end);
    }).toList();
  }

  /// Kembalikan transaksi pada bulan [year]/[month] (1–12).
  static List<TransactionModel> filterMonth(
    List<TransactionModel> txList, {
    required int year,
    required int month,
  }) {
    final from = DateTime(year, month);
    final until = DateTime(year, month + 1); // Dart menangani overflow bulan
    return filterPeriod(txList, from: from, until: until);
  }

  // ── Agregasi ─────────────────────────────────────────────────────────────

  /// Total pemasukan dari daftar transaksi.
  static BigInt totalIncome(List<TransactionModel> txList) => txList
      .where((t) => t.isIncome)
      .fold(BigInt.zero, (s, t) => s + Rupiah.exact(t.amount));

  /// Total pengeluaran dari daftar transaksi.
  static BigInt totalExpense(List<TransactionModel> txList) => txList
      .where((t) => !t.isIncome)
      .fold(BigInt.zero, (s, t) => s + Rupiah.exact(t.amount));

  /// Arus kas bersih = pemasukan − pengeluaran.
  static BigInt netCashFlow(List<TransactionModel> txList) =>
      totalIncome(txList) - totalExpense(txList);

  /// Rasio tabungan = (pemasukan − pengeluaran) / pemasukan × 100.
  ///
  /// Kembalikan `null` jika pemasukan nol (tidak dapat dibagi).
  /// Nilai negatif sah (pengeluaran melebihi pemasukan).
  static double? savingsRate(List<TransactionModel> txList) {
    final inc = totalIncome(txList);
    if (inc == BigInt.zero) return null;
    return (inc - totalExpense(txList)) / inc * 100;
  }

  // ── Kategori ─────────────────────────────────────────────────────────────

  /// Pengeluaran dikelompokkan per kategori.
  /// Urutan: nilai terbesar dulu.
  static Map<String, BigInt> expenseByCategory(List<TransactionModel> txList) {
    final map = <String, BigInt>{};
    for (final t in txList.where((t) => !t.isIncome)) {
      map[t.category] =
          (map[t.category] ?? BigInt.zero) + Rupiah.exact(t.amount);
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  // ── Seri bulanan ─────────────────────────────────────────────────────────

  /// Kembalikan seri [MonthlySummary] untuk [monthCount] bulan terakhir
  /// yang berakhir pada [referenceMonth].
  ///
  /// Bulan tanpa transaksi tetap muncul dengan nilai nol.
  /// [referenceMonth] default = bulan kalender saat ini.
  static List<MonthlySummary> monthlySeries(
    List<TransactionModel> txList, {
    int monthCount = 6,
    DateTime? referenceMonth,
  }) {
    final ref = referenceMonth ?? DateTime.now();
    // Mulai dari referenceMonth ke belakang sebanyak monthCount bulan
    final result = <MonthlySummary>[];
    for (var i = monthCount - 1; i >= 0; i--) {
      // Mundur i bulan dari bulan referensi
      final year = ref.year;
      final month = ref.month - i;
      // Biarkan Dart menangani wrap (mis. bulan 0 → Desember tahun lalu)
      final target = DateTime(year, month);
      final txMonth = filterMonth(
        txList,
        year: target.year,
        month: target.month,
      );
      result.add(
        MonthlySummary(
          year: target.year,
          month: target.month,
          income: totalIncome(txMonth),
          expense: totalExpense(txMonth),
        ),
      );
    }
    return result;
  }

  // ── Urutan ───────────────────────────────────────────────────────────────

  /// Urutkan transaksi: tanggal terbaru dulu; jika sama, ID sebagai
  /// pembanding stabil (lexicographic ascending).
  static List<TransactionModel> sorted(List<TransactionModel> txList) {
    final copy = List<TransactionModel>.from(txList);
    copy.sort((a, b) {
      final dateCmp = b.date.compareTo(a.date);
      if (dateCmp != 0) return dateCmp;
      return a.id.compareTo(b.id);
    });
    return copy;
  }
}

/// Ringkasan pemasukan dan pengeluaran satu bulan.
class MonthlySummary {
  final int year;
  final int month;
  final BigInt income;
  final BigInt expense;

  const MonthlySummary({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });

  /// Label pendek bulan dalam Bahasa Indonesia (Jan–Des).
  String get shortLabel {
    const labels = [
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
    ];
    return labels[month - 1];
  }

  /// Label bulan + tahun, mis. "Sep 2026".
  String get fullLabel => '$shortLabel $year';

  BigInt get netCashFlow => income - expense;

  @override
  String toString() => 'MonthlySummary($fullLabel, inc:$income, exp:$expense)';
}
