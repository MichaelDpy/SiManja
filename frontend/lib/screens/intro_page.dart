import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Halaman pengenalan SIMANJA.
///
/// Alur: Splash → **Intro** → Login → Home
///
/// Semua tombol di halaman ini menuju /login — tidak ada jalan pintas ke /home.
/// Anggota 3 akan memasang auth gate di SplashPage setelah commit ini.
///
/// Layout:
/// - Portrait: Column yang dapat digulir via SingleChildScrollView
///   saat konten tidak muat (skala teks besar, layar sempit).
/// - Landscape / lebar ≥ 600 dp: Row dua kolom yang tetap dapat digulir —
///   grafik kiri, teks + CTA kanan.
class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  void _goToLogin(BuildContext context) {
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width >= 600 ||
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: isLandscape
            ? _LandscapeLayout(onLogin: () => _goToLogin(context))
            : _PortraitLayout(onLogin: () => _goToLogin(context)),
      ),
    );
  }
}

// ── Portrait layout ───────────────────────────────────────────────────────

class _PortraitLayout extends StatelessWidget {
  final VoidCallback onLogin;

  const _PortraitLayout({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandRow(),
          const SizedBox(height: 40),
          const Center(child: _GraphicWidget()),
          const SizedBox(height: 40),
          _HeadlineSection(tt: tt, cs: cs),
          const SizedBox(height: 40),
          _CtaSection(onLogin: onLogin, cs: cs),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Landscape layout ──────────────────────────────────────────────────────

class _LandscapeLayout extends StatelessWidget {
  final VoidCallback onLogin;

  const _LandscapeLayout({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        // Kolom kiri: grafik (scrollable jika tinggi sempit)
        const Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: _GraphicWidget(),
            ),
          ),
        ),
        // Kolom kanan: teks + CTA
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandRow(),
                const SizedBox(height: 24),
                _HeadlineSection(tt: tt, cs: cs),
                const SizedBox(height: 28),
                _CtaSection(onLogin: onLogin, cs: cs),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Sub-widget bersama ────────────────────────────────────────────────────

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.account_balance_wallet,
            color: cs.onPrimary,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'SIMANJA',
          style: GoogleFonts.lato(
            color: AppColors.teal,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _GraphicWidget extends StatelessWidget {
  const _GraphicWidget();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(
          color: AppColors.teal.withValues(alpha: 0.15),
          width: 2,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.teal.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.insert_chart_outlined_rounded,
                color: AppColors.teal,
                size: 64,
              ),
              const SizedBox(height: 8),
              Text(
                'Keuangan Anda',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const Positioned(
            top: 28,
            right: 28,
            child: _FloatingBadge(
              icon: Icons.trending_up,
              color: AppColors.income,
              label: '+12%',
            ),
          ),
          const Positioned(
            bottom: 28,
            left: 28,
            child: _FloatingBadge(
              icon: Icons.savings,
              color: AppColors.chart2,
              label: 'Nabung',
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadlineSection extends StatelessWidget {
  final TextTheme tt;
  final ColorScheme cs;

  const _HeadlineSection({required this.tt, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kelola Keuangan\nLebih Mudah\nBersama SIMANJA.',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Pantau pengeluaran, aset, dan tren keuangan dalam satu aplikasi yang bersih dan mudah digunakan.',
          style: tt.bodyMedium?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FeaturePill(label: '📊 Grafik Aset'),
            _FeaturePill(label: '💳 Transaksi'),
            _FeaturePill(label: '📈 Analitik'),
            _FeaturePill(label: '🔒 Aman'),
          ],
        ),
      ],
    );
  }
}

class _CtaSection extends StatelessWidget {
  final VoidCallback onLogin;
  final ColorScheme cs;

  const _CtaSection({required this.onLogin, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onLogin,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Mulai Sekarang',
              style: GoogleFonts.lato(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: onLogin,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
            child: Text(
              'Sudah punya akun? Masuk',
              style: GoogleFonts.lato(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Komponen kecil ────────────────────────────────────────────────────────

class _FloatingBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _FloatingBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.lato(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String label;

  const _FeaturePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.lato(
          color: AppColors.teal,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
