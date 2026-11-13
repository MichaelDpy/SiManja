import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/finance_summary.dart';
import '../core/theme.dart';
import '../models/transaction_model.dart';
import '../widgets/app_widgets.dart';

// ── Formatter ─────────────────────────────────────────────────────────────

final _currencyFmt = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

// ── Warna kategori deterministik ──────────────────────────────────────────
// Urutan tetap agar warna tidak berubah saat data berubah.

const _kCategoryColors = [
  AppColors.chart1,
  AppColors.chart2,
  AppColors.chart3,
  AppColors.chart4,
  AppColors.chart5,
  AppColors.chart6,
  AppColors.income,
  AppColors.expense,
];

Color _colorForCategory(String name, int index) {
  // Prioritas: indeks tampilan (deterministik terhadap urutan sort)
  return _kCategoryColors[index % _kCategoryColors.length];
}

// ── Singkatan sumbu ───────────────────────────────────────────────────────

String _axisLabel(double v) {
  if (v == 0) return '0';
  if (v >= 1_000_000) return '${(v / 1_000_000).toStringAsFixed(0)}jt';
  if (v >= 1_000) return '${(v / 1_000).toStringAsFixed(0)}rb';
  return v.toStringAsFixed(0);
}

// ── AnalyticsPage ─────────────────────────────────────────────────────────

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  // Bulan akhir rentang — default: bulan kalender sekarang
  late DateTime _referenceMonth;
  static const int _monthCount = 6;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _referenceMonth = DateTime(now.year, now.month);
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // ── Derived data ──────────────────────────────────────────────────────

  List<TransactionModel> get _allTx => AppState.instance.transactions;

  /// Seri 6 bulan berakhir di [_referenceMonth].
  List<MonthlySummary> get _series => FinanceSummary.monthlySeries(
    _allTx,
    monthCount: _monthCount,
    referenceMonth: _referenceMonth,
  );

  /// Semua transaksi dalam rentang 6 bulan.
  List<TransactionModel> get _rangeTx {
    final first = _series.first;
    final last = _series.last;
    return FinanceSummary.filterPeriod(
      _allTx,
      from: DateTime(first.year, first.month),
      until: DateTime(last.year, last.month + 1),
    );
  }

  double get _totalIncome => FinanceSummary.totalIncome(_rangeTx);
  double get _totalExpense => FinanceSummary.totalExpense(_rangeTx);
  double get _netSavings => _totalIncome - _totalExpense;
  double? get _savingsRate => FinanceSummary.savingsRate(_rangeTx);

  double get _avgIncome {
    final sum = _series.fold(0.0, (s, m) => s + m.income);
    return sum / _monthCount;
  }

  double get _avgExpense {
    final sum = _series.fold(0.0, (s, m) => s + m.expense);
    return sum / _monthCount;
  }

  Map<String, double> get _expenseByCategory =>
      FinanceSummary.expenseByCategory(_rangeTx);

  // ── Navigasi periode ──────────────────────────────────────────────────

  void _prevPeriod() => setState(
    () => _referenceMonth = DateTime(
      _referenceMonth.year,
      _referenceMonth.month - 1,
    ),
  );

  void _nextPeriod() {
    final now = DateTime.now();
    final next = DateTime(_referenceMonth.year, _referenceMonth.month + 1);
    // Tidak boleh melebihi bulan sekarang
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() => _referenceMonth = next);
    }
  }

  bool get _canGoNext {
    final now = DateTime.now();
    return _referenceMonth.isBefore(DateTime(now.year, now.month));
  }

  String get _rangeLabel {
    final first = _series.first;
    final last = _series.last;
    if (first.year == last.year) {
      return '${first.shortLabel}–${last.shortLabel} ${last.year}';
    }
    return '${first.shortLabel} ${first.year}–${last.shortLabel} ${last.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final cs = Theme.of(context).colorScheme;

    if (state.transactionsLoading) {
      return const Scaffold(
        body: AppLoadingPage(message: 'Memuat data analitik...'),
      );
    }

    if (state.transactionsError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analitik & Tren')),
        body: AppErrorState(
          message: state.transactionsError!,
          retryLabel: 'Muat Ulang',
          onRetry: () => AppState.instance.retryTransactions(),
        ),
      );
    }

    final series = _series;
    final expCat = _expenseByCategory;
    final hasData = _rangeTx.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analitik & Tren'),
        actions: [
          // Pemilih bulan akhir
          _PeriodStepper(
            label: _rangeLabel,
            onPrev: _prevPeriod,
            onNext: _canGoNext ? _nextPeriod : null,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Kartu Metrik ───────────────────────────────────────────
            _buildMetricGrid(cs),

            const SizedBox(height: 20),

            // ── Grafik batang ─────────────────────────────────────────
            _buildBarChart(series, hasData),

            const SizedBox(height: 20),

            // ── Rincian pengeluaran ───────────────────────────────────
            _buildExpenseBreakdown(expCat, hasData),

            const SizedBox(height: 20),

            // ── Tren tabungan (line chart) ────────────────────────────
            _buildSavingsTrend(series, hasData),
          ],
        ),
      ),
    );
  }

  // ── Metric Grid ───────────────────────────────────────────────────────

  Widget _buildMetricGrid(ColorScheme cs) {
    final savingsRate = _savingsRate;
    final rateLabel = savingsRate == null
        ? '—'
        : '${savingsRate.toStringAsFixed(1)}%';

    // Gunakan LayoutBuilder agar kartu tidak overflow di layar sempit
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final twoCol = constraints.maxWidth >= 300;
        final cards = [
          _MetricCard(
            label: 'Rata-rata Pemasukan/Bln',
            value: _currencyFmt.format(_avgIncome),
            icon: Icons.arrow_downward,
            color: AppColors.income,
          ),
          _MetricCard(
            label: 'Rata-rata Pengeluaran/Bln',
            value: _currencyFmt.format(_avgExpense),
            icon: Icons.arrow_upward,
            color: AppColors.expense,
          ),
          _MetricCard(
            label: 'Tabungan Bersih',
            value: _currencyFmt.format(_netSavings),
            icon: Icons.savings_outlined,
            color: AppColors.teal,
          ),
          _MetricCard(
            label: 'Rasio Tabungan',
            value: rateLabel,
            icon: Icons.percent,
            color: AppColors.chart2,
            subtitle: savingsRate == null ? 'Pemasukan nol' : null,
          ),
        ];

        if (twoCol) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Column(
          children: cards
              .map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: c,
                ),
              )
              .toList(),
        );
      },
    );
  }

  // ── Bar Chart ─────────────────────────────────────────────────────────

  Widget _buildBarChart(List<MonthlySummary> series, bool hasData) {
    final cs = Theme.of(context).colorScheme;

    // maxY dari max(income, expense) semua bulan; fallback 1 jika semua nol
    final maxVal = series.fold<double>(
      1,
      (m, s) => [m, s.income, s.expense].reduce((a, b) => a > b ? a : b),
    );
    final chartMax = maxVal * 1.25;
    // interval tidak boleh nol — fl_chart crash jika nol
    final interval = (chartMax / 4).ceilToDouble().clamp(1.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pemasukan vs Pengeluaran',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _LegendDot(color: AppColors.income, label: 'Masuk'),
              const SizedBox(width: 10),
              _LegendDot(color: AppColors.expense, label: 'Keluar'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _rangeLabel,
            style: GoogleFonts.lato(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          if (!hasData)
            const AppEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'Belum Ada Data',
              description: 'Tambahkan transaksi untuk melihat grafik.',
            )
          else
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: chartMax,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(context).dividerColor,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => cs.surface,
                      tooltipBorder: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final m = series[groupIndex];
                        final isIncome = rodIndex == 0;
                        final label = isIncome ? 'Pemasukan' : 'Pengeluaran';
                        final val = isIncome ? m.income : m.expense;
                        return BarTooltipItem(
                          '${m.shortLabel} ${m.year}\n',
                          GoogleFonts.lato(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                          children: [
                            TextSpan(
                              text: '$label\n',
                              style: GoogleFonts.lato(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            TextSpan(
                              text: _currencyFmt.format(val),
                              style: GoogleFonts.lato(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isIncome
                                    ? AppColors.income
                                    : AppColors.expense,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: interval,
                        getTitlesWidget: (v, meta) {
                          if (v == 0 || v == meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            _axisLabel(v),
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
                        getTitlesWidget: (v, meta) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= series.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              series[idx].shortLabel,
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
                  barGroups: series.asMap().entries.map((e) {
                    final m = e.value;
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: m.income,
                          color: AppColors.income,
                          width: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: m.expense,
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
    );
  }

  // ── Expense Breakdown ─────────────────────────────────────────────────

  Widget _buildExpenseBreakdown(Map<String, double> expCat, bool hasData) {
    final cs = Theme.of(context).colorScheme;
    final maxVal = expCat.isEmpty
        ? 1.0
        : expCat.values.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rincian Pengeluaran',
            style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _rangeLabel,
            style: GoogleFonts.lato(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          if (!hasData || expCat.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Belum ada pengeluaran pada periode ini',
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            ...expCat.entries.toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final cat = entry.value.key;
              final val = entry.value.value;
              final color = _colorForCategory(cat, idx);
              // Guard bagi nol: maxVal selalu >= 1 karena inisialisasi di atas
              final ratio = val / maxVal;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    // Warna legend — tidak hanya mengandalkan warna
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 100,
                      child: Text(
                        cat,
                        style: GoogleFonts.lato(
                          color: cs.onSurfaceVariant,
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
                          value: ratio,
                          backgroundColor: Theme.of(context).dividerColor,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: Text(
                        _currencyFmt.format(val),
                        style: GoogleFonts.lato(
                          color: cs.onSurface,
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
            }),
        ],
      ),
    );
  }

  // ── Savings Trend ─────────────────────────────────────────────────────

  Widget _buildSavingsTrend(List<MonthlySummary> series, bool hasData) {
    final cs = Theme.of(context).colorScheme;

    // Nilai tabungan per bulan
    final spots = series.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.netCashFlow);
    }).toList();

    // maxY / minY — tangani semua nilai nol dan nilai negatif
    final values = series.map((m) => m.netCashFlow).toList();
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs();
    // Beri padding 20%; minimal range 1 agar fl_chart tidak crash
    final padding = range > 0 ? range * 0.2 : 1000.0;
    final chartMax = maxV + padding;
    final chartMin = minV - padding;
    final interval = ((chartMax - chartMin) / 4).ceilToDouble().clamp(
      1.0,
      double.infinity,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tren Tabungan Bersih',
            style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _rangeLabel,
            style: GoogleFonts.lato(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          if (!hasData)
            const AppEmptyState(
              icon: Icons.show_chart_outlined,
              title: 'Belum Ada Data',
              description: 'Tambahkan transaksi untuk melihat tren.',
            )
          else
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: chartMin,
                  maxY: chartMax,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Theme.of(context).dividerColor,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => cs.surface,
                      tooltipBorder: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                      getTooltipItems: (spots) => spots.map((s) {
                        final m = series[s.spotIndex];
                        return LineTooltipItem(
                          '${m.shortLabel} ${m.year}\n',
                          GoogleFonts.lato(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                          children: [
                            TextSpan(
                              text: _currencyFmt.format(s.y),
                              style: GoogleFonts.lato(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: s.y >= 0
                                    ? AppColors.income
                                    : AppColors.expense,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
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
                        getTitlesWidget: (v, meta) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= series.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              series[idx].shortLabel,
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
                      spots: spots,
                      isCurved: true,
                      color: AppColors.teal,
                      barWidth: 2.5,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, pct, bar, idx) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: spot.y >= 0
                                  ? AppColors.teal
                                  : AppColors.expense,
                              strokeWidth: 2,
                              strokeColor: cs.surface,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.teal.withValues(alpha: 0.2),
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
    );
  }
}

// ── Period Stepper ─────────────────────────────────────────────────────────

class _PeriodStepper extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _PeriodStepper({
    required this.label,
    required this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: onPrev,
          tooltip: 'Periode sebelumnya',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.lato(
              color: AppColors.teal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            size: 20,
            color: onNext != null ? null : AppColors.textMuted,
          ),
          onPressed: onNext,
          tooltip: 'Periode berikutnya',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ── Metric Card ────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
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
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.lato(
                    color: cs.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legend Dot ─────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
