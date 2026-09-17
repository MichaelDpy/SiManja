import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top logo / brand row
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.teal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: AppColors.bgDark,
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
              ),

              const Spacer(flex: 2),

              // Decorative graphic
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.bgCard,
                    border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.15),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // outer ring
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
                      // icon cluster
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.insert_chart_outlined_rounded,
                            color: AppColors.teal,
                            size: 64,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Keuangan Anda',
                            style: GoogleFonts.lato(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      // small floating badge top-right
                      Positioned(
                        top: 28,
                        right: 28,
                        child: _FloatingBadge(
                          icon: Icons.trending_up,
                          color: AppColors.income,
                          label: '+12%',
                        ),
                      ),
                      // small floating badge bottom-left
                      Positioned(
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
                ),
              ),

              const Spacer(flex: 2),

              // Main headline
              Text(
                'Kelola Keuangan\nLebih Mudah dan Manis\nBersama Simanja.',
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 16),

              // Subtitle
              Text(
                'Pantau pengeluaran, aset, dan tren keuangan Anda dalam satu aplikasi yang bersih dan mudah digunakan.',
                style: GoogleFonts.lato(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 12),

              // Feature pills
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _FeaturePill(label: '📊 Grafik Aset'),
                  _FeaturePill(label: '💳 Transaksi'),
                  _FeaturePill(label: '📈 Analitik'),
                  _FeaturePill(label: '🔒 Aman'),
                ],
              ),

              const Spacer(flex: 3),

              // CTA button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: AppColors.bgDark,
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

              // Skip / login hint
              Center(
                child: GestureDetector(
                  onTap: () =>
                      Navigator.of(context).pushReplacementNamed('/home'),
                  child: Text(
                    'Lewati untuk sekarang',
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textMuted,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
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
