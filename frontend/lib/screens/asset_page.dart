import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/mock_data.dart';

class AssetPage extends StatefulWidget {
  const AssetPage({super.key});

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  int _touchedIndex = -1;
  final _fmt =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final total = MockData.totalAssets;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Ringkasan Aset'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Total header ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text(
                    'Total Aset Bersih',
                    style: GoogleFonts.lato(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fmt.format(total),
                    style: GoogleFonts.lato(
                      color: AppColors.teal,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.trending_up,
                          color: AppColors.income, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '+4.2% bulan ini',
                        style: GoogleFonts.lato(
                          color: AppColors.income,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Large Donut Chart ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Distribusi Portfolio',
                    style: GoogleFonts.lato(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              touchCallback: (event, response) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      response == null ||
                                      response.touchedSection == null) {
                                    _touchedIndex = -1;
                                    return;
                                  }
                                  _touchedIndex = response
                                      .touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            sections: MockData.assets.asMap().entries.map((e) {
                              final isTouched = e.key == _touchedIndex;
                              return PieChartSectionData(
                                value: e.value.value,
                                color: e.value.color,
                                radius: isTouched ? 90 : 78,
                                title: isTouched
                                    ? '${e.value.percentage.toStringAsFixed(1)}%'
                                    : '',
                                titleStyle: GoogleFonts.lato(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.bgDark,
                                ),
                              );
                            }).toList(),
                            centerSpaceRadius: 60,
                            sectionsSpace: 3,
                          ),
                        ),
                        // Center label
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _touchedIndex >= 0
                                  ? MockData
                                      .assets[_touchedIndex].name
                                      .split(' ')
                                      .first
                                  : 'Total',
                              style: GoogleFonts.lato(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _touchedIndex >= 0
                                  ? _fmt.format(
                                      MockData.assets[_touchedIndex].value)
                                  : _fmt.format(total),
                              style: GoogleFonts.lato(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Asset Detail List ────────────────────────────────────────
            Text(
              'Detail Aset',
              style: GoogleFonts.lato(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...MockData.assets.map((a) => _AssetDetailCard(
                  asset: a,
                  total: total,
                  fmt: _fmt,
                )),
          ],
        ),
      ),
    );
  }
}

class _AssetDetailCard extends StatelessWidget {
  final AssetModel asset;
  final double total;
  final NumberFormat fmt;

  const _AssetDetailCard({
    required this.asset,
    required this.total,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: asset.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconForAsset(asset.name),
                  color: asset.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      style: GoogleFonts.lato(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${asset.percentage.toStringAsFixed(1)}% dari total',
                      style: GoogleFonts.lato(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                fmt.format(asset.value),
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: asset.value / total,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(asset.color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForAsset(String name) {
    if (name.contains('Bank') || name.contains('Rekening')) {
      return Icons.account_balance;
    } else if (name.contains('Investasi')) {
      return Icons.trending_up;
    } else if (name.contains('Tabungan')) {
      return Icons.savings;
    } else if (name.contains('Darurat')) {
      return Icons.shield;
    } else if (name.contains('Digital') || name.contains('Dompet')) {
      return Icons.wallet;
    }
    return Icons.category;
  }
}
