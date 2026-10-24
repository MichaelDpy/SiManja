import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';
import '../core/app_state.dart';
import '../widgets/section_header.dart';
import '../widgets/account_card.dart';

class DashboardPage extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const DashboardPage({super.key, this.onNavigateToTab});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _touchedIndex = -1;
  final _fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
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

  void _showNotifications() {
    final state = AppState.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Notifikasi',
                  style: GoogleFonts.lato(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(
                  state.notifEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: state.notifEnabled
                      ? AppColors.teal
                      : AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!state.notifEnabled)
              Center(
                child: Text(
                  'Notifikasi dinonaktifkan.\nAktifkan di halaman Profil.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              )
            else ...[
              _NotifItem(
                icon: Icons.savings_outlined,
                color: AppColors.income,
                title: 'Tabungan bertambah',
                subtitle: 'Saldo rekening utama diperbarui',
                time: 'Baru saja',
              ),
              const SizedBox(height: 10),
              _NotifItem(
                icon: Icons.warning_amber_outlined,
                color: AppColors.chart6,
                title: 'Pengeluaran tinggi',
                subtitle: 'Pengeluaran bulan ini melebihi rata-rata',
                time: '1 jam lalu',
              ),
              const SizedBox(height: 10),
              _NotifItem(
                icon: Icons.trending_up,
                color: AppColors.chart2,
                title: 'Investasi naik 2.3%',
                subtitle: 'Portofolio reksa dana kamu meningkat',
                time: '3 jam lalu',
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selamat Datang 👋',
                          style: GoogleFonts.lato(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          state.name,
                          style: GoogleFonts.lato(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Lonceng notifikasi
                    Stack(
                      children: [
                        IconButton(
                          onPressed: _showNotifications,
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (state.notifEnabled)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.expense,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    // Avatar profil
                    GestureDetector(
                      onTap: () => widget.onNavigateToTab?.call(5),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.teal.withValues(alpha: 0.2),
                        backgroundImage: state.photoPath != null
                            ? FileImage(File(state.photoPath!))
                            : null,
                        child: state.photoPath == null
                            ? const Icon(
                                Icons.person,
                                color: AppColors.teal,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Total Balance Card ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.teal.withValues(alpha: 0.25),
                        AppColors.teal.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.teal.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Aset',
                        style: GoogleFonts.lato(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fmt.format(MockData.totalAssets),
                        style: GoogleFonts.lato(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _BalanceStat(
                            label: 'Pemasukan',
                            value: _fmt.format(state.totalIncome),
                            color: AppColors.income,
                            icon: Icons.arrow_downward,
                          ),
                          const SizedBox(width: 24),
                          _BalanceStat(
                            label: 'Pengeluaran',
                            value: _fmt.format(state.totalExpense),
                            color: AppColors.expense,
                            icon: Icons.arrow_upward,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Donut Chart ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            'Distribusi Aset',
                            style: GoogleFonts.lato(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Sep 2026',
                            style: GoogleFonts.lato(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: PieChart(
                                PieChartData(
                                  pieTouchData: PieTouchData(
                                    touchCallback: (event, response) {
                                      setState(() {
                                        if (!event
                                                .isInterestedForInteractions ||
                                            response == null ||
                                            response.touchedSection == null) {
                                          _touchedIndex = -1;
                                          return;
                                        }
                                        _touchedIndex = response
                                            .touchedSection!
                                            .touchedSectionIndex;
                                      });
                                    },
                                  ),
                                  sections: MockData.assets.asMap().entries.map((
                                    e,
                                  ) {
                                    final isTouched = e.key == _touchedIndex;
                                    return PieChartSectionData(
                                      value: e.value.percentage,
                                      color: e.value.color,
                                      radius: isTouched ? 70 : 58,
                                      title: isTouched
                                          ? '${e.value.percentage.toStringAsFixed(1)}%'
                                          : '',
                                      titleStyle: GoogleFonts.lato(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.bgDark,
                                      ),
                                    );
                                  }).toList(),
                                  centerSpaceRadius: 48,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: MockData.assets
                                    .map((a) => _LegendItem(asset: a))
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Accounts ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: SectionHeader(
                  title: 'Rekening & Akun',
                  actionLabel: 'Lihat Semua',
                  onAction: () => widget.onNavigateToTab?.call(2),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: AccountCard(account: MockData.accounts[i]),
                ),
                childCount: MockData.accounts.length,
              ),
            ),

            // ── Recent Transactions ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: SectionHeader(
                  title: 'Transaksi Terbaru',
                  actionLabel: 'Lihat Semua',
                  onAction: () => widget.onNavigateToTab?.call(2),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final tx = state.transactions[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _TransactionTile(tx: tx, fmt: _fmt),
                  );
                },
                childCount: state.transactions.length > 5
                    ? 5
                    : state.transactions.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _NotifItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const _NotifItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.lato(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Text(
          time,
          style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _BalanceStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 11),
            ),
            Text(
              value,
              style: GoogleFonts.lato(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final AssetModel asset;
  const _LegendItem({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: asset.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              asset.name,
              style: GoogleFonts.lato(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${asset.percentage.toStringAsFixed(1)}%',
            style: GoogleFonts.lato(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  final NumberFormat fmt;

  const _TransactionTile({required this.tx, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final sign = tx.isIncome ? '+' : '-';
    final color = tx.isIncome ? AppColors.income : AppColors.expense;

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tx.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(tx.icon, color: tx.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  style: GoogleFonts.lato(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  tx.category,
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$sign${fmt.format(tx.amount)}',
            style: GoogleFonts.lato(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
