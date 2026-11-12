import 'package:flutter/material.dart';

import 'theme.dart';
import '../models/transaction_model.dart';

// Re-export agar import lama (import '../core/mock_data.dart') tetap valid.
export '../models/transaction_model.dart' show TransactionModel, CategoryMeta;

// ── Model-model lokal yang belum dipindah ─────────────────────────────────

class AccountModel {
  final String name;
  final String subtitle;
  final double balance;
  final IconData icon;
  final Color color;

  const AccountModel({
    required this.name,
    required this.subtitle,
    required this.balance,
    required this.icon,
    required this.color,
  });
}

class AssetModel {
  final String name;
  final double value;
  final double percentage;
  final Color color;

  const AssetModel({
    required this.name,
    required this.value,
    required this.percentage,
    required this.color,
  });
}

class MonthlyDataModel {
  final String month;
  final double income;
  final double expense;

  const MonthlyDataModel({
    required this.month,
    required this.income,
    required this.expense,
  });
}

class TableRowModel {
  final int no;
  final String kategori;
  final double jumlah;
  final String keterangan;
  final DateTime tanggal;

  const TableRowModel({
    required this.no,
    required this.kategori,
    required this.jumlah,
    required this.keterangan,
    required this.tanggal,
  });
}

// ── Model pengguna demo ───────────────────────────────────────────────────

/// Data profil pengguna demo untuk tahap frontend lokal.
///
/// ⚠ KHUSUS DEMO — C2/C3 wajib menghapus ketergantungan autentikasi
/// pada objek ini setelah Firebase Auth aktif. Email dan password di sini
/// hanya untuk smoke-test login lokal, bukan kredensial produksi.
class DemoUser {
  final String name;
  final String email;

  /// Password demo — HANYA untuk validasi login lokal tahap frontend.
  /// Firebase Auth akan menggantikan ini; hapus field ini saat C2 aktif.
  final String password;
  final String phone;
  final String address;
  final String city;
  final String job;
  final double monthlyIncome;

  const DemoUser({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.address,
    required this.city,
    required this.job,
    required this.monthlyIncome,
  });
}

// ── Mock Data ─────────────────────────────────────────────────────────────

class MockData {
  MockData._();

  /// Profil pengguna demo. Lihat peringatan [DemoUser].
  static const DemoUser dummyUser = DemoUser(
    name: 'Budi Santoso',
    email: 'budi@demo.simanja',
    password: 'demo1234', // ← hapus saat Firebase Auth aktif (C2)
    phone: '+62 812-3456-7890',
    address: 'Jl. Merdeka No. 10',
    city: 'Jakarta',
    job: 'Software Engineer',
    monthlyIncome: 10_000_000,
  );

  static const List<AccountModel> accounts = [
    AccountModel(
      name: 'Rekening Utama',
      subtitle: 'BCA · 1234-5678',
      balance: 24_500_000,
      icon: Icons.account_balance,
      color: AppColors.teal,
    ),
    AccountModel(
      name: 'Tabungan',
      subtitle: 'Mandiri · 8765-4321',
      balance: 18_750_000,
      icon: Icons.savings,
      color: AppColors.chart2,
    ),
    AccountModel(
      name: 'Dana Darurat',
      subtitle: 'BNI · 1122-3344',
      balance: 10_000_000,
      icon: Icons.shield,
      color: AppColors.chart3,
    ),
    AccountModel(
      name: 'Investasi',
      subtitle: 'Reksa Dana',
      balance: 32_000_000,
      icon: Icons.trending_up,
      color: AppColors.chart4,
    ),
    AccountModel(
      name: 'Dompet Digital',
      subtitle: 'GoPay / OVO',
      balance: 1_250_000,
      icon: Icons.wallet,
      color: AppColors.chart5,
    ),
  ];

  /// Tanggal acuan fixture demo.
  ///
  /// Semua data contoh dibuat relatif terhadap tanggal ini sehingga
  /// bisa direproduksi pada tes tanpa bergantung pada waktu nyata.
  /// Gunakan [demoAnchor] di tes, jangan pakai DateTime.now().
  static final DateTime demoAnchor = DateTime(2026, 11, 1);

  /// Transaksi contoh bertanggal relatif terhadap [demoAnchor].
  ///
  /// Mencakup 6 bulan (Jun–Nov 2026) dengan bulan tanpa transaksi
  /// sengaja dibiarkan kosong untuk menguji seri bulanan nol.
  static List<TransactionModel> get transactions {
    final a = demoAnchor; // Nov 2026
    return [
      // ── Nov 2026 ─────────────────────────────────────────────────
      TransactionModel(
        id: 'TRX001',
        category: 'Gaji',
        description: 'Gaji Bulan November',
        amount: 8_500_000,
        isIncome: true,
        date: DateTime(a.year, a.month, 1),
      ),
      TransactionModel(
        id: 'TRX002',
        category: 'Makan & Minum',
        description: 'Belanja Bulanan',
        amount: 1_200_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 3),
      ),
      TransactionModel(
        id: 'TRX003',
        category: 'Transportasi',
        description: 'Bensin & Parkir',
        amount: 450_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 5),
      ),
      TransactionModel(
        id: 'TRX004',
        category: 'Tagihan',
        description: 'Listrik & Internet',
        amount: 780_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 7),
      ),
      TransactionModel(
        id: 'TRX005',
        category: 'Kesehatan',
        description: 'Apotek & Vitamin',
        amount: 320_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 9),
      ),
      TransactionModel(
        id: 'TRX006',
        category: 'Investasi',
        description: 'Top-up Reksa Dana',
        amount: 2_000_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 10),
      ),
      TransactionModel(
        id: 'TRX007',
        category: 'Hiburan',
        description: 'Streaming & Game',
        amount: 250_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 12),
      ),
      TransactionModel(
        id: 'TRX008',
        category: 'Transfer Masuk',
        description: 'Bayar Hutang Teman',
        amount: 500_000,
        isIncome: true,
        date: DateTime(a.year, a.month, 13),
      ),
      TransactionModel(
        id: 'TRX009',
        category: 'Pendidikan',
        description: 'Kursus Online',
        amount: 650_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 14),
      ),
      TransactionModel(
        id: 'TRX010',
        category: 'Belanja',
        description: 'Pakaian & Aksesori',
        amount: 890_000,
        isIncome: false,
        date: DateTime(a.year, a.month, 14),
      ),
      // ── Okt 2026 ─────────────────────────────────────────────────
      TransactionModel(
        id: 'TRX011',
        category: 'Gaji',
        description: 'Gaji Bulan Oktober',
        amount: 8_500_000,
        isIncome: true,
        date: DateTime(a.year, a.month - 1, 1),
      ),
      TransactionModel(
        id: 'TRX012',
        category: 'Makan & Minum',
        description: 'Makan Siang Kantor',
        amount: 950_000,
        isIncome: false,
        date: DateTime(a.year, a.month - 1, 15),
      ),
      TransactionModel(
        id: 'TRX013',
        category: 'Tagihan',
        description: 'Pulsa & Internet',
        amount: 200_000,
        isIncome: false,
        date: DateTime(a.year, a.month - 1, 20),
      ),
      // ── Sep 2026 ─────────────────────────────────────────────────
      TransactionModel(
        id: 'TRX014',
        category: 'Gaji',
        description: 'Gaji Bulan September',
        amount: 8_500_000,
        isIncome: true,
        date: DateTime(a.year, a.month - 2, 1),
      ),
      TransactionModel(
        id: 'TRX015',
        category: 'Belanja',
        description: 'Elektronik',
        amount: 3_500_000,
        isIncome: false,
        date: DateTime(a.year, a.month - 2, 10),
      ),
      // Agu 2026 sengaja kosong untuk tes seri nol
      // ── Jul 2026 ─────────────────────────────────────────────────
      TransactionModel(
        id: 'TRX016',
        category: 'Gaji',
        description: 'Gaji Bulan Juli',
        amount: 8_500_000,
        isIncome: true,
        date: DateTime(a.year, a.month - 4, 1),
      ),
      TransactionModel(
        id: 'TRX017',
        category: 'Transfer Masuk',
        description: 'Bonus Proyek',
        amount: 2_000_000,
        isIncome: true,
        date: DateTime(a.year, a.month - 4, 15),
      ),
      TransactionModel(
        id: 'TRX018',
        category: 'Hiburan',
        description: 'Liburan',
        amount: 4_000_000,
        isIncome: false,
        date: DateTime(a.year, a.month - 4, 20),
      ),
      // ── Jun 2026 ─────────────────────────────────────────────────
      TransactionModel(
        id: 'TRX019',
        category: 'Gaji',
        description: 'Gaji Bulan Juni',
        amount: 8_500_000,
        isIncome: true,
        date: DateTime(a.year, a.month - 5, 1),
      ),
      TransactionModel(
        id: 'TRX020',
        category: 'Investasi',
        description: 'Beli Saham',
        amount: 5_000_000,
        isIncome: false,
        date: DateTime(a.year, a.month - 5, 5),
      ),
    ];
  }

  static const List<AssetModel> assets = [
    AssetModel(
      name: 'Rekening Bank',
      value: 24_500_000,
      percentage: 28.7,
      color: AppColors.teal,
    ),
    AssetModel(
      name: 'Investasi',
      value: 32_000_000,
      percentage: 37.5,
      color: AppColors.chart2,
    ),
    AssetModel(
      name: 'Tabungan',
      value: 18_750_000,
      percentage: 22.0,
      color: AppColors.chart3,
    ),
    AssetModel(
      name: 'Dana Darurat',
      value: 10_000_000,
      percentage: 11.7,
      color: AppColors.chart4,
    ),
    AssetModel(
      name: 'Dompet Digital',
      value: 1_250_000,
      percentage: 1.5,
      color: AppColors.chart5,
    ),
    AssetModel(
      name: 'Lainnya',
      value: 500_000,
      percentage: 0.6,
      color: AppColors.chart6,
    ),
  ];

  static const List<MonthlyDataModel> monthlyData = [
    MonthlyDataModel(month: 'Jun', income: 8_500_000, expense: 5_000_000),
    MonthlyDataModel(month: 'Jul', income: 10_500_000, expense: 4_000_000),
    MonthlyDataModel(month: 'Ags', income: 0, expense: 0),
    MonthlyDataModel(month: 'Sep', income: 8_500_000, expense: 3_500_000),
    MonthlyDataModel(month: 'Okt', income: 8_500_000, expense: 1_150_000),
    MonthlyDataModel(month: 'Nov', income: 9_000_000, expense: 6_540_000),
  ];

  static List<TableRowModel> get tableRows {
    final txs = transactions;
    return txs.asMap().entries.map((e) {
      final t = e.value;
      return TableRowModel(
        no: e.key + 1,
        kategori: t.category,
        jumlah: t.isIncome ? t.amount : -t.amount,
        keterangan: t.description,
        tanggal: t.date,
      );
    }).toList();
  }

  static double get totalAssets => assets.fold(0, (sum, a) => sum + a.value);

  static double get totalIncome =>
      transactions.where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  static double get totalExpense =>
      transactions.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount);

  static double get netBalance => totalIncome - totalExpense;
}
