import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Model transaksi yang dapat disimpan ke Firestore.
///
/// Tidak mengandung [IconData] atau [Color] — keduanya bukan tipe serializable.
/// Presentasi ikon dan warna diperoleh dari [CategoryMeta.of(category)].
///
/// Kontrak field (lihat 00-panduan-tim.md § Kontrak antarmodul):
/// - [id]          : ID stabil, tidak berubah saat edit.
/// - [category]    : String label; gunakan [CategoryMeta.knownCategories] sebagai referensi.
/// - [description] : Teks keterangan bebas, tidak boleh kosong.
/// - [amount]      : Rupiah bulat positif finite (`double`, integer semantik).
///                   Firestore menyimpan sebagai integer; konversi hanya setelah validasi.
/// - [isIncome]    : true = pemasukan, false = pengeluaran.
/// - [date]        : Tanggal transaksi (bukan waktu server).
class TransactionModel {
  final String id;
  final String category;
  final String description;
  final double amount;
  final bool isIncome;
  final DateTime date;

  const TransactionModel({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.date,
  });

  /// Validasi domain: amount harus finite, positif, dan merupakan bilangan bulat.
  /// Lempar [ArgumentError] jika tidak valid.
  static void validate(double amount) {
    if (!amount.isFinite) throw ArgumentError('amount harus finite');
    if (amount <= 0) throw ArgumentError('amount harus positif');
    if (amount != amount.roundToDouble()) {
      throw ArgumentError('amount harus bilangan bulat rupiah');
    }
  }

  /// Buat salinan dengan field yang diperbarui; [id] tidak bisa diubah.
  TransactionModel copyWith({
    String? category,
    String? description,
    double? amount,
    bool? isIncome,
    DateTime? date,
  }) {
    return TransactionModel(
      id: id,
      category: category ?? this.category,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      isIncome: isIncome ?? this.isIncome,
      date: date ?? this.date,
    );
  }

  @override
  bool operator ==(Object other) => other is TransactionModel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TransactionModel(id:$id, category:$category, amount:$amount, '
      'isIncome:$isIncome, date:${date.toIso8601String()})';
}

// ── Pemetaan kategori → ikon & warna ──────────────────────────────────────

/// Metadata presentasi untuk satu kategori.
///
/// Dipakai di lapisan UI; **tidak** disimpan ke Firestore.
class CategoryMeta {
  final String name;
  final IconData icon;
  final Color color;
  final bool isIncome;

  const CategoryMeta({
    required this.name,
    required this.icon,
    required this.color,
    required this.isIncome,
  });

  /// Daftar semua kategori yang dikenal aplikasi.
  static const List<CategoryMeta> knownCategories = [
    // ── Pemasukan ──────────────────────────────────────────────────────
    CategoryMeta(
      name: 'Gaji',
      icon: Icons.work,
      color: AppColors.income,
      isIncome: true,
    ),
    CategoryMeta(
      name: 'Transfer Masuk',
      icon: Icons.swap_horiz,
      color: AppColors.income,
      isIncome: true,
    ),
    CategoryMeta(
      name: 'Investasi Masuk',
      icon: Icons.trending_up,
      color: AppColors.income,
      isIncome: true,
    ),
    CategoryMeta(
      name: 'Lainnya (Masuk)',
      icon: Icons.add_circle_outline,
      color: AppColors.income,
      isIncome: true,
    ),
    // ── Pengeluaran ────────────────────────────────────────────────────
    CategoryMeta(
      name: 'Makan & Minum',
      icon: Icons.restaurant,
      color: AppColors.chart3,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Transportasi',
      icon: Icons.directions_car,
      color: AppColors.chart2,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Tagihan',
      icon: Icons.bolt,
      color: AppColors.chart6,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Kesehatan',
      icon: Icons.local_hospital,
      color: AppColors.chart4,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Investasi',
      icon: Icons.trending_up,
      color: AppColors.teal,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Hiburan',
      icon: Icons.movie,
      color: AppColors.chart4,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Pendidikan',
      icon: Icons.school,
      color: AppColors.chart5,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Belanja',
      icon: Icons.shopping_bag,
      color: AppColors.chart3,
      isIncome: false,
    ),
    CategoryMeta(
      name: 'Lainnya (Keluar)',
      icon: Icons.remove_circle_outline,
      color: AppColors.expense,
      isIncome: false,
    ),
  ];

  /// Cari metadata untuk [categoryName]. Jika tidak ditemukan, kembalikan
  /// fallback generik agar UI tidak crash.
  static CategoryMeta of(String categoryName) {
    return knownCategories.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => CategoryMeta(
        name: categoryName,
        icon: Icons.receipt_long_outlined,
        color: AppColors.neutral,
        isIncome: false,
      ),
    );
  }
}
