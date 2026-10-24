import 'package:flutter/material.dart';
import 'theme.dart';

// ── Models ─────────────────────────────────────────────────────────────────

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

class TransactionModel {
  final String id;
  final String category;
  final String description;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final IconData icon;
  final Color color;

  const TransactionModel({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.date,
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

// ── Mock Data ───────────────────────────────────────────────────────────────

class MockData {
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

  static final List<TransactionModel> transactions = [
    TransactionModel(
      id: 'TRX001',
      category: 'Gaji',
      description: 'Gaji Bulan September',
      amount: 8_500_000,
      isIncome: true,
      date: DateTime(2026, 9, 1),
      icon: Icons.work,
      color: AppColors.income,
    ),
    TransactionModel(
      id: 'TRX002',
      category: 'Makan & Minum',
      description: 'Belanja Bulanan',
      amount: 1_200_000,
      isIncome: false,
      date: DateTime(2026, 9, 3),
      icon: Icons.restaurant,
      color: AppColors.chart3,
    ),
    TransactionModel(
      id: 'TRX003',
      category: 'Transportasi',
      description: 'Bensin & Parkir',
      amount: 450_000,
      isIncome: false,
      date: DateTime(2026, 9, 5),
      icon: Icons.directions_car,
      color: AppColors.chart2,
    ),
    TransactionModel(
      id: 'TRX004',
      category: 'Tagihan',
      description: 'Listrik & Internet',
      amount: 780_000,
      isIncome: false,
      date: DateTime(2026, 9, 7),
      icon: Icons.bolt,
      color: AppColors.chart6,
    ),
    TransactionModel(
      id: 'TRX005',
      category: 'Kesehatan',
      description: 'Apotek & Vitamin',
      amount: 320_000,
      isIncome: false,
      date: DateTime(2026, 9, 9),
      icon: Icons.local_hospital,
      color: AppColors.chart4,
    ),
    TransactionModel(
      id: 'TRX006',
      category: 'Investasi',
      description: 'Top-up Reksa Dana',
      amount: 2_000_000,
      isIncome: false,
      date: DateTime(2026, 9, 10),
      icon: Icons.trending_up,
      color: AppColors.teal,
    ),
    TransactionModel(
      id: 'TRX007',
      category: 'Hiburan',
      description: 'Streaming & Game',
      amount: 250_000,
      isIncome: false,
      date: DateTime(2026, 9, 12),
      icon: Icons.movie,
      color: AppColors.chart4,
    ),
    TransactionModel(
      id: 'TRX008',
      category: 'Transfer Masuk',
      description: 'Bayar Hutang Teman',
      amount: 500_000,
      isIncome: true,
      date: DateTime(2026, 9, 13),
      icon: Icons.swap_horiz,
      color: AppColors.income,
    ),
    TransactionModel(
      id: 'TRX009',
      category: 'Pendidikan',
      description: 'Kursus Online',
      amount: 650_000,
      isIncome: false,
      date: DateTime(2026, 9, 14),
      icon: Icons.school,
      color: AppColors.chart5,
    ),
    TransactionModel(
      id: 'TRX010',
      category: 'Belanja',
      description: 'Pakaian & Aksesori',
      amount: 890_000,
      isIncome: false,
      date: DateTime(2026, 9, 14),
      icon: Icons.shopping_bag,
      color: AppColors.chart3,
    ),
  ];

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
    MonthlyDataModel(month: 'Apr', income: 9_000_000, expense: 5_200_000),
    MonthlyDataModel(month: 'Mei', income: 8_500_000, expense: 4_800_000),
    MonthlyDataModel(month: 'Jun', income: 9_200_000, expense: 6_100_000),
    MonthlyDataModel(month: 'Jul', income: 8_800_000, expense: 5_500_000),
    MonthlyDataModel(month: 'Ags', income: 9_500_000, expense: 5_900_000),
    MonthlyDataModel(month: 'Sep', income: 9_000_000, expense: 6_540_000),
  ];

  static final List<TableRowModel> tableRows = [
    TableRowModel(
      no: 1,
      kategori: 'Gaji',
      jumlah: 8_500_000,
      keterangan: 'Gaji pokok September',
      tanggal: DateTime(2026, 9, 1),
    ),
    TableRowModel(
      no: 2,
      kategori: 'Makan & Minum',
      jumlah: -1_200_000,
      keterangan: 'Belanja Indomaret & warung',
      tanggal: DateTime(2026, 9, 3),
    ),
    TableRowModel(
      no: 3,
      kategori: 'Transportasi',
      jumlah: -450_000,
      keterangan: 'Bensin motor & grab',
      tanggal: DateTime(2026, 9, 5),
    ),
    TableRowModel(
      no: 4,
      kategori: 'Tagihan',
      jumlah: -780_000,
      keterangan: 'PLN & Indihome',
      tanggal: DateTime(2026, 9, 7),
    ),
    TableRowModel(
      no: 5,
      kategori: 'Kesehatan',
      jumlah: -320_000,
      keterangan: 'K24 Apotek vitamin C',
      tanggal: DateTime(2026, 9, 9),
    ),
    TableRowModel(
      no: 6,
      kategori: 'Investasi',
      jumlah: -2_000_000,
      keterangan: 'Top-up reksa dana pasar uang',
      tanggal: DateTime(2026, 9, 10),
    ),
    TableRowModel(
      no: 7,
      kategori: 'Hiburan',
      jumlah: -250_000,
      keterangan: 'Netflix & Spotify',
      tanggal: DateTime(2026, 9, 12),
    ),
    TableRowModel(
      no: 8,
      kategori: 'Transfer Masuk',
      jumlah: 500_000,
      keterangan: 'Piutang Budi lunas',
      tanggal: DateTime(2026, 9, 13),
    ),
    TableRowModel(
      no: 9,
      kategori: 'Pendidikan',
      jumlah: -650_000,
      keterangan: 'Udemy Flutter course',
      tanggal: DateTime(2026, 9, 14),
    ),
    TableRowModel(
      no: 10,
      kategori: 'Belanja',
      jumlah: -890_000,
      keterangan: 'Shopee pakaian bulanan',
      tanggal: DateTime(2026, 9, 14),
    ),
  ];

  static double get totalAssets =>
      assets.fold(0, (sum, a) => sum + a.value);

  static double get totalIncome => transactions
      .where((t) => t.isIncome)
      .fold(0, (sum, t) => sum + t.amount);

  static double get totalExpense => transactions
      .where((t) => !t.isIncome)
      .fold(0, (sum, t) => sum + t.amount);

  static double get netBalance => totalIncome - totalExpense;
}
