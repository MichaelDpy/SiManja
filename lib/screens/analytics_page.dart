import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  // Category expense breakdown
  final Map<String, double> _categoryExpense = {
    'Makan': 1_200_000,
    'Transport': 450_000,
    'Tagihan': 780_000,
    'Kesehatan': 320_000,
    'Investasi': 2_000_000,
    'Hiburan': 250_000,
    'Pendidikan': 650_000,
    'Belanja': 890_000,
  };

  @override
  Widget build(BuildContext context) {
    final data = MockData.monthlyData;
    final maxVal = data.fold<double>(0, (m, d) => d.income > m ? d.income : m);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Analitik & Tren'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '6 Bulan',
              style: GoogleFonts.lato(
                color: AppColors.teal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Metric Cards ─────────────────────────────────────────────
            Row(
              children: [
                _MetricCard(
                  label: 'Rata-rata Pemasukan',
                  value: _fmt.format(
                    data.fold<double>(0, (s, d) => s + d.income) / data.length,
                  ),
                  icon: Icons.arrow_downward,
                  color: AppColors.income,
                ),
                const SizedBox(width: 12),
                _MetricCard(
                  label: 'Rata-rata Pengeluaran',
                  value: _fmt.format(
                    data.fold<double>(0, (s, d) => s + d.expense) / data.length,
                  ),
                  icon: Icons.arrow_upward,
                  color: AppColors.expense,
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                _MetricCard(
                  label: 'Tabungan Bersih',
                  value: _fmt.format(
                    data.fold<double>(0, (s, d) => s + d.income - d.expense),
                  ),
                  icon: Icons.savings,
                  color: AppColors.teal,
                ),
                const SizedBox(width: 12),
                _MetricCard(
                  label: 'Rasio Tabungan',
                  value: '27.4%',
                  icon: Icons.percent,
                  color: AppColors.chart2,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Grouped Bar Chart ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Pemasukan vs Pengeluaran',
                        style: GoogleFonts.lato(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      _ChartLegendDot(color: AppColors.income, label: 'Masuk'),
                      const SizedBox(width: 12),
                      _ChartLegendDot(
                        color: AppColors.expense,
                        label: 'Keluar',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        maxY: maxVal * 1.2,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxVal * 0.3,
                          getDrawingHorizontalLine: (_) =>
                              FlLine(color: AppColors.divider, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 48,
                              getTitlesWidget: (v, _) {
                                if (v == 0) return const SizedBox();
                                final label = v >= 1_000_000
                                    ? '${(v / 1_000_000).toStringAsFixed(0)}jt'
                                    : '${(v / 1_000).toStringAsFixed(0)}rb';
                                return Text(
                                  label,
                                  style: GoogleFonts.lato(
                                    color: AppColors.textMuted,
                                    fontSize: 9,
                                  ),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= data.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    data[idx].month,
                                    style: GoogleFonts.lato(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: data.asMap().entries.map((e) {
                          return BarChartGroupData(
                            x: e.key,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.income,
                                color: AppColors.income,
                                width: 10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              BarChartRodData(
                                toY: e.value.expense,
                                color: AppColors.expense,
                                width: 10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                            barsSpace: 4,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Expense Breakdown ─────────────────────────────────────────
            Text(
              'Rincian Pengeluaran',
              style: GoogleFonts.lato(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: _categoryExpense.entries
                    .map(
                      (e) => _ExpenseBar(
                        label: e.key,
                        value: e.value,
                        maxValue: _categoryExpense.values.reduce(
                          (a, b) => a > b ? a : b,
                        ),
                        fmt: _fmt,
                      ),
                    )
                    .toList(),
              ),
            ),

            const SizedBox(height: 24),

            // ── Savings trend line placeholder ────────────────────────────
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
                    'Tren Tabungan',
                    style: GoogleFonts.lato(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 140,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) =>
                              FlLine(color: AppColors.divider, strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= data.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    data[idx].month,
                                    style: GoogleFonts.lato(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: data.asMap().entries.map((e) {
                              return FlSpot(
                                e.key.toDouble(),
                                e.value.income - e.value.expense,
                              );
                            }).toList(),
                            isCurved: true,
                            color: AppColors.teal,
                            barWidth: 3,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (_, s2, p2, p3) =>
                                  FlDotCirclePainter(
                                    radius: 4,
                                    color: AppColors.teal,
                                    strokeWidth: 2,
                                    strokeColor: AppColors.bgCard,
                                  ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.teal.withValues(alpha: 0.25),
                                  AppColors.teal.withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    value,
                    style: GoogleFonts.lato(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseBar extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final NumberFormat fmt;

  const _ExpenseBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      AppColors.teal,
      AppColors.chart2,
      AppColors.chart3,
      AppColors.chart4,
      AppColors.chart5,
      AppColors.chart6,
      AppColors.income,
      AppColors.expense,
    ];
    final color = colors[label.hashCode.abs() % colors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: GoogleFonts.lato(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / maxValue,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 7,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              fmt.format(value),
              style: GoogleFonts.lato(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _ChartLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}
