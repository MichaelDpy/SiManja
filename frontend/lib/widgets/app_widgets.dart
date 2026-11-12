/// Widget utilitas bersama SIMANJA.
///
/// Menyediakan:
/// - [AppSpacing]  — konstanta jarak yang konsisten
/// - [AppLoadingIndicator] — spinner bertema
/// - [AppEmptyState] — tampilan data kosong
/// - [AppErrorState] — tampilan error dengan tombol coba lagi
/// - [AppStatusBadge] — pill pemasukan/pengeluaran
///
/// Semua widget mengambil warna dari [Theme.of(context)] agar berjalan
/// benar di tema terang maupun gelap.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';

// ── Spacing constants ─────────────────────────────────────────────────────

/// Konstanta spasi standar agar seluruh halaman konsisten.
abstract final class AppSpacing {
  /// 4 dp — jarak sangat rapat (mis. antara ikon dan teks inline)
  static const double xs = 4;

  /// 8 dp — jarak rapat (mis. antar baris dalam kartu)
  static const double sm = 8;

  /// 12 dp — jarak sedang kecil
  static const double md = 12;

  /// 16 dp — jarak sedang (padding dalam kartu)
  static const double lg = 16;

  /// 20 dp — jarak lebar (padding halaman horisontal)
  static const double xl = 20;

  /// 24 dp — jarak antar seksi
  static const double xxl = 24;

  /// 32 dp — jarak besar (antar blok konten)
  static const double xxxl = 32;

  /// Padding horisontal standar halaman: 20 dp kiri-kanan.
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: xl);

  /// Padding untuk konten dalam kartu.
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

// ── Loading ───────────────────────────────────────────────────────────────

/// Spinner melingkar dengan warna primer tema.
///
/// Gunakan di tengah halaman atau di dalam kartu saat data dimuat.
class AppLoadingIndicator extends StatelessWidget {
  /// Ukuran area widget (spinner dibatasi setengah dari ini). Default 48.
  final double size;

  const AppLoadingIndicator({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        backgroundColor: color.withValues(alpha: 0.15),
      ),
    );
  }
}

/// Widget loading bertata letak penuh — cocok sebagai pengganti konten
/// halaman saat sedang memuat.
class AppLoadingPage extends StatelessWidget {
  final String? message;

  const AppLoadingPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoadingIndicator(size: 48),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────

/// Tampilan "tidak ada data" dengan ikon, judul, dan deskripsi opsional.
///
/// ```dart
/// AppEmptyState(
///   icon: Icons.receipt_long_outlined,
///   title: 'Belum ada transaksi',
///   description: 'Tambahkan transaksi pertamamu.',
///   action: ElevatedButton(onPressed: ..., child: Text('Tambah')),
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: cs.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description!,
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────

/// Tampilan error dengan pesan dan tombol "Coba Lagi" opsional.
///
/// ```dart
/// AppErrorState(
///   message: 'Gagal memuat data. Periksa koneksi internet.',
///   onRetry: () => context.read<MyBloc>().add(RetryEvent()),
/// )
/// ```
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Coba Lagi',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: cs.error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Terjadi Kesalahan',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: tt.bodyMedium, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────

/// Pill kecil yang menunjukkan jenis transaksi: pemasukan atau pengeluaran.
///
/// ```dart
/// AppStatusBadge(isIncome: tx.isIncome)
/// ```
class AppStatusBadge extends StatelessWidget {
  final bool isIncome;

  const AppStatusBadge({super.key, required this.isIncome});

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? AppColors.income : AppColors.expense;
    final label = isIncome ? 'Pemasukan' : 'Pengeluaran';
    final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Divider tipis ─────────────────────────────────────────────────────────

/// Divider horizontal tipis yang mengikuti warna divider tema.
class AppDivider extends StatelessWidget {
  final double? indent;
  final double? endIndent;

  const AppDivider({super.key, this.indent, this.endIndent});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: Theme.of(context).dividerColor,
    );
  }
}
