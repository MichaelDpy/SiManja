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
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Notifikasi',
                  style: Theme.of(sheetCtx).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Icon(
                  state.notifEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: state.notifEnabled
                      ? AppColors.teal
                      : Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
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
                  style: Theme.of(sheetCtx).textTheme.bodyMedium,
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
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          state.name,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Lonceng notifikasi
                    Stack(
                      children: [
                        IconButton(
                          onPressed: _showNotifications,
                          icon: Icon(
                            Icons.notifications_outlined,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fmt.format(MockData.totalAssets),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
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
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            'Sep 2026',
                            style: Theme.of(context).textTheme.bodySmall,
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
    final tt = Theme.of(context).textTheme;
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
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(subtitle, style: tt.bodySmall),
            ],
          ),
        ),
        Text(time, style: tt.bodySmall),
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
    final tt = Theme.of(context).textTheme;
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
            Text(label, style: tt.bodySmall),
            Text(
              value,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
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
    final tt = Theme.of(context).textTheme;
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
              style: tt.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${asset.percentage.toStringAsFixed(1)}%',
            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
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
    final tt = Theme.of(context).textTheme;
    final sign = tx.isIncome ? '+' : '-';
    final amountColor = tx.isIncome ? AppColors.income : AppColors.expense;

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
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  tx.category,
                  style: tt.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$sign${fmt.format(tx.amount)}',
            style: tt.bodyMedium?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
