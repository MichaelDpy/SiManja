import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';
import '../core/app_state.dart';
import '../core/finance_summary.dart';
import '../widgets/section_header.dart';
import '../widgets/account_card.dart';

/// Model periode untuk filter ringkasan arus kas di Dasbor.
class _DashboardPeriod {
  final int? year;
  final int? month;
  final String label;

  const _DashboardPeriod({this.year, this.month, required this.label});

  const _DashboardPeriod.all()
      : year = null,
        month = null,
        label = 'Semua';

  bool get isAll => year == null;

  @override
  bool operator ==(Object other) =>
      other is _DashboardPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Data notifikasi dalam aplikasi yang diturunkan dari transaksi aktual.
class InAppNotificationItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  const InAppNotificationItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  /// Membangun daftar notifikasi dalam aplikasi berdasarkan transaksi aktual dan periode terpilih.
  static List<InAppNotificationItem> buildSummary({
    required List<TransactionModel> transactions,
    String periodLabel = 'Semua',
    NumberFormat? currencyFormatter,
  }) {
    if (transactions.isEmpty) return const [];

    final fmt = currencyFormatter ??
        NumberFormat.currency(
          locale: 'id_ID',
          symbol: 'Rp ',
          decimalDigits: 0,
        );

    final list = <InAppNotificationItem>[];
    final totalIncome = FinanceSummary.totalIncome(transactions);
    final totalExpense = FinanceSummary.totalExpense(transactions);
    final netCashFlow = FinanceSummary.netCashFlow(transactions);
    final savingsRate = FinanceSummary.savingsRate(transactions);
    final expenses = FinanceSummary.expenseByCategory(transactions);

    // 1. Transaksi terakhir tercatat
    final latest = transactions.first;
    final formattedDate =
        DateFormat('d MMM yyyy', 'id_ID').format(latest.date);
    list.add(
      InAppNotificationItem(
        icon: latest.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
        color: latest.isIncome ? AppColors.income : AppColors.expense,
        title: latest.isIncome ? 'Pemasukan Terakhir' : 'Pengeluaran Terakhir',
        subtitle:
            '${latest.description} (${latest.category}) sebesar ${fmt.format(latest.amount)}',
        time: formattedDate,
      ),
    );

    // 2. Status Arus Kas Periode Ini
    if (netCashFlow < 0) {
      list.add(
        InAppNotificationItem(
          icon: Icons.warning_amber_rounded,
          color: AppColors.expense,
          title: 'Defisit Arus Kas',
          subtitle:
              'Pengeluaran (${fmt.format(totalExpense)}) melebihi pemasukan (${fmt.format(totalIncome)}).',
          time: periodLabel,
        ),
      );
    } else if (netCashFlow > 0) {
      list.add(
        InAppNotificationItem(
          icon: Icons.trending_up,
          color: AppColors.income,
          title: 'Surplus Arus Kas',
          subtitle:
              'Arus kas positif +${fmt.format(netCashFlow)} tercatat pada periode ini.',
          time: periodLabel,
        ),
      );
    } else if (totalIncome > 0 && totalExpense > 0) {
      list.add(
        InAppNotificationItem(
          icon: Icons.balance,
          color: AppColors.teal,
          title: 'Arus Kas Seimbang',
          subtitle: 'Pemasukan dan pengeluaran bernilai sama.',
          time: periodLabel,
        ),
      );
    }

    // 3. Kategori Pengeluaran Terbesar
    if (expenses.isNotEmpty) {
      final top = expenses.entries.first;
      final meta = CategoryMeta.of(top.key);
      list.add(
        InAppNotificationItem(
          icon: meta.icon,
          color: meta.color,
          title: 'Pengeluaran Terbesar: ${top.key}',
          subtitle:
              'Total ${fmt.format(top.value)} dialokasikan untuk kategori ${top.key}.',
          time: periodLabel,
        ),
      );
    }

    // 4. Evaluasi Rasio Tabungan
    if (savingsRate != null) {
      if (savingsRate >= 20) {
        list.add(
          InAppNotificationItem(
            icon: Icons.savings_outlined,
            color: AppColors.income,
            title: 'Rasio Tabungan Baik (${savingsRate.toStringAsFixed(1)}%)',
            subtitle:
                'Anda berhasil menyisihkan ${savingsRate.toStringAsFixed(1)}% dari total pemasukan.',
            time: periodLabel,
          ),
        );
      } else if (savingsRate > 0) {
        list.add(
          InAppNotificationItem(
            icon: Icons.savings_outlined,
            color: AppColors.chart6,
            title: 'Rasio Tabungan Rendah (${savingsRate.toStringAsFixed(1)}%)',
            subtitle:
                'Pemasukan tersisa ${savingsRate.toStringAsFixed(1)}% setelah seluruh pengeluaran.',
            time: periodLabel,
          ),
        );
      }
    }

    return list;
  }
}

class DashboardPage extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateToTab;

  const DashboardPage({super.key, this.onNavigateToTab});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _touchedIndex = -1;
  _DashboardPeriod _selectedPeriod = const _DashboardPeriod.all();

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

  /// Membangun daftar pilihan periode dari seri transaksi 6 bulan terakhir.
  List<_DashboardPeriod> _buildPeriods(List<TransactionModel> txList) {
    final list = <_DashboardPeriod>[const _DashboardPeriod.all()];
    final ref = txList.isNotEmpty ? txList.first.date : DateTime.now();
    final series = FinanceSummary.monthlySeries(
      txList,
      monthCount: 6,
      referenceMonth: ref,
    );

    // Tampilkan bulan dari yang terbaru ke terlama
    for (final m in series.reversed) {
      final dt = DateTime(m.year, m.month);
      final label = DateFormat('MMM yyyy', 'id_ID').format(dt);
      list.add(_DashboardPeriod(year: m.year, month: m.month, label: label));
    }
    return list;
  }

  /// Filter transaksi berdasarkan periode aktif.
  List<TransactionModel> _filterTransactions(List<TransactionModel> txList) {
    if (_selectedPeriod.isAll) {
      return txList;
    }
    return FinanceSummary.filterMonth(
      txList,
      year: _selectedPeriod.year!,
      month: _selectedPeriod.month!,
    );
  }

  /// Membangun notifikasi dalam aplikasi yang dapat diverifikasi dari data transaksi.
  List<InAppNotificationItem> _buildInAppNotifications(
    List<TransactionModel> txList,
    _DashboardPeriod period,
  ) {
    return InAppNotificationItem.buildSummary(
      transactions: txList,
      periodLabel: period.isAll ? 'Semua' : period.label,
      currencyFormatter: _fmt,
    );
  }

  void _showNotifications() {
    final state = AppState.instance;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final filteredTx = _filterTransactions(state.transactions);
    final notifItems = _buildInAppNotifications(filteredTx, _selectedPeriod);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pegangan modal (handle bar)
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header ringkasan
                  Row(
                    children: [
                      Icon(
                        state.notifEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        color: state.notifEnabled
                            ? AppColors.teal
                            : cs.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ringkasan Aktivitas',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Dalam aplikasi • bukan push notification/FCM',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.notifEnabled && notifItems.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _selectedPeriod.isAll
                                ? 'Semua'
                                : _selectedPeriod.label,
                            style: GoogleFonts.lato(
                              color: AppColors.teal,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Konten berdasarkan status notifikasi dan data
                  if (!state.notifEnabled) ...[
                    // Kondisi preferensi nonaktif
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 40,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Notifikasi Dinonaktifkan',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ringkasan aktivitas dalam aplikasi sedang nonaktif.\nAktifkan kembali melalui menu Profil.',
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              widget.onNavigateToTab?.call(5); // Ke Profil
                            },
                            icon: const Icon(Icons.person_outline, size: 16),
                            label: const Text('Buka Pengaturan Profil'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              minimumSize: const Size(44, 40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (notifItems.isEmpty) ...[
                    // Empty state saat tidak ada transaksi pada periode terpilih
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 40,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedPeriod.isAll
                                ? 'Belum Ada Transaksi'
                                : 'Tidak Ada Aktivitas di ${_selectedPeriod.label}',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Catat transaksi baru untuk melihat ringkasan aktivitas dalam aplikasi.',
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              widget.onNavigateToTab?.call(2); // Ke Transaksi
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Tambah Transaksi'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              minimumSize: const Size(44, 40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Daftar ringkasan yang diturunkan dari transaksi riil
                    ...notifItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NotifItem(
                          icon: item.icon,
                          color: item.color,
                          title: item.title,
                          subtitle: item.subtitle,
                          time: item.time,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            widget.onNavigateToTab?.call(2); // Ke Transaksi
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          widget.onNavigateToTab?.call(2);
                        },
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Kelola Transaksi'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // Filter transaksi untuk ringkasan arus kas
    final periods = _buildPeriods(state.transactions);
    final filteredTx = _filterTransactions(state.transactions);

    // Perhitungan ringkasan keuangan dari utility A3
    final totalIncome = FinanceSummary.totalIncome(filteredTx);
    final totalExpense = FinanceSummary.totalExpense(filteredTx);
    final netCashFlow = FinanceSummary.netCashFlow(filteredTx);
    final savingsRate = FinanceSummary.savingsRate(filteredTx);

    // Perhitungan total dan persentase aset nyata dari nilai
    final totalAssetValue =
        MockData.assets.fold<double>(0.0, (sum, a) => sum + a.value);

    // Transaksi terbaru dibatasi maksimal 5
    final recentTx = filteredTx.take(5).toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar / Header ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selamat Datang 👋',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.name,
                            style: tt.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Lonceng notifikasi
                    IconButton(
                      onPressed: _showNotifications,
                      icon: Icon(
                        state.notifEnabled
                            ? Icons.notifications_outlined
                            : Icons.notifications_off_outlined,
                        color: state.notifEnabled
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      tooltip: state.notifEnabled
                          ? 'Ringkasan Aktivitas'
                          : 'Notifikasi Dinonaktifkan',
                    ),
                    const SizedBox(width: 4),
                    // Avatar profil
                    GestureDetector(
                      onTap: () => widget.onNavigateToTab?.call(5),
                      child: CircleAvatar(
                        radius: 19,
                        backgroundColor: AppColors.teal.withValues(alpha: 0.2),
                        backgroundImage: state.photoPath != null
                            ? FileImage(File(state.photoPath!))
                            : null,
                        child: state.photoPath == null
                            ? const Icon(
                                Icons.person,
                                color: AppColors.teal,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Banner Loading State ─────────────────────────────────────
            if (state.transactionsLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.teal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppColors.teal),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Memuat transaksi...',
                            style: tt.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Banner Error State & Tombol Retry ─────────────────────────
            if (state.transactionsError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.expense.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.expense,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gagal memuat transaksi',
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.expense,
                                ),
                              ),
                              Text(
                                state.transactionsError!,
                                style: tt.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => state.retryTransactions(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Coba Lagi'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.expense,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Pemilih Periode Arus Kas ─────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                child: SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: periods.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final p = periods[i];
                      final isSelected = p == _selectedPeriod;
                      return ChoiceChip(
                        label: Text(p.label),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => _selectedPeriod = p),
                        labelStyle: GoogleFonts.lato(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : cs.onSurface,
                        ),
                        selectedColor: AppColors.teal,
                        backgroundColor: cs.surface,
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.teal
                              : cs.outline.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Kartu Ringkasan Arus Kas Transaksi ───────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.teal.withValues(alpha: 0.18),
                        AppColors.teal.withValues(alpha: 0.04),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.swap_horiz,
                                size: 18,
                                color: AppColors.teal,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Arus Kas Transaksi',
                                style: tt.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _selectedPeriod.isAll
                                  ? 'Semua Riwayat'
                                  : _selectedPeriod.label,
                              style: GoogleFonts.lato(
                                color: AppColors.teal,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Arus Kas Bersih',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          netCashFlow > 0
                              ? '+${_fmt.format(netCashFlow)}'
                              : (netCashFlow < 0
                                  ? '-${_fmt.format(netCashFlow.abs())}'
                                  : _fmt.format(0)),
                          style: tt.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: netCashFlow > 0
                                ? AppColors.income
                                : (netCashFlow < 0
                                    ? AppColors.expense
                                    : cs.onSurface),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        color: cs.outline.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _BalanceStat(
                              label: 'Pemasukan',
                              value: _fmt.format(totalIncome),
                              color: AppColors.income,
                              icon: Icons.arrow_downward,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceStat(
                              label: 'Pengeluaran',
                              value: _fmt.format(totalExpense),
                              color: AppColors.expense,
                              icon: Icons.arrow_upward,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceStat(
                              label: 'Tabungan',
                              value: savingsRate != null
                                  ? '${savingsRate.toStringAsFixed(1)}%'
                                  : '—',
                              color: AppColors.chart2,
                              icon: Icons.savings_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Kartu Nilai Aset Terpisah (Data Contoh) ───────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => widget.onNavigateToTab?.call(1),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.donut_large,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Total Nilai Aset',
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Data contoh',
                                  style: GoogleFonts.lato(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _fmt.format(totalAssetValue),
                              style: tt.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Estimasi nilai dari ${MockData.accounts.length} rekening & aset contoh',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    'Detail',
                                    style: GoogleFonts.lato(
                                      color: cs.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Diagram Donut Distribusi Aset (Data Contoh) ───────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Distribusi Aset',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.onSurfaceVariant
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Data contoh',
                              style: GoogleFonts.lato(
                                color: cs.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${MockData.assets.length} Aset',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 320;

                          final legendItems = MockData.assets.map((a) {
                            final pct = totalAssetValue > 0
                                ? (a.value / totalAssetValue) * 100
                                : 0.0;
                            return _LegendItem(asset: a, percentage: pct);
                          }).toList();

                          final chart = PieChart(
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
                                    _touchedIndex = response.touchedSection!
                                        .touchedSectionIndex;
                                  });
                                },
                              ),
                              sections: MockData.assets.asMap().entries.map((e) {
                                final isTouched = e.key == _touchedIndex;
                                final pct = totalAssetValue > 0
                                    ? (e.value.value / totalAssetValue) * 100
                                    : 0.0;
                                return PieChartSectionData(
                                  value: e.value.value,
                                  color: e.value.color,
                                  radius: isTouched ? 48 : 40,
                                  title: isTouched
                                      ? '${pct.toStringAsFixed(1)}%'
                                      : '',
                                  titleStyle: GoogleFonts.lato(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                );
                              }).toList(),
                              centerSpaceRadius: 36,
                              sectionsSpace: 2,
                            ),
                          );

                          if (isNarrow) {
                            return Column(
                              children: [
                                SizedBox(
                                  height: 160,
                                  child: chart,
                                ),
                                const SizedBox(height: 14),
                                Column(children: legendItems),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: SizedBox(
                                  height: 170,
                                  child: chart,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 6,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: legendItems,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Rekening & Akun ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'Rekening & Akun',
                      actionLabel: 'Lihat Semua',
                      onAction: () => widget.onNavigateToTab?.call(1),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Data contoh • belum terhubung ke transaksi',
                            style: GoogleFonts.lato(
                              color: cs.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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

            // ── Transaksi Terbaru ────────────────────────────────────────
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

            // Tampilkan daftar transaksi atau empty state saat periode kosong
            if (recentTx.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 38,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedPeriod.isAll
                              ? 'Belum ada transaksi tercatat'
                              : 'Tidak ada transaksi pada ${_selectedPeriod.label}',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedPeriod.isAll
                              ? 'Transaksi yang ditambahkan akan muncul di sini.'
                              : 'Pilih periode lain atau tambah transaksi baru.',
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => widget.onNavigateToTab?.call(2),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Tambah Transaksi'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: const Size(44, 36),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final tx = recentTx[i];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: _TransactionTile(
                        tx: tx,
                        fmt: _fmt,
                        onTap: () => widget.onNavigateToTab?.call(2),
                      ),
                    );
                  },
                  childCount: recentTx.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

// ── Item Notifikasi Dalam Aplikasi ─────────────────────────────────────────

class _NotifItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;
  final VoidCallback? onTap;

  const _NotifItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Widget Statistik Arus Kas ──────────────────────────────────────────────

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
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Item Legenda Aset ──────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final AssetModel asset;
  final double percentage;

  const _LegendItem({
    required this.asset,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: asset.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              asset.name,
              style: tt.bodySmall?.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: tt.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tile Transaksi Terbaru ─────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  final NumberFormat fmt;
  final VoidCallback? onTap;

  const _TransactionTile({
    required this.tx,
    required this.fmt,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final sign = tx.isIncome ? '+' : '-';
    final amountColor = tx.isIncome ? AppColors.income : AppColors.expense;
    final meta = CategoryMeta.of(tx.category);
    final formattedDate = DateFormat('d MMM yyyy', 'id_ID').format(tx.date);

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta.icon, color: meta.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description,
                      style:
                          tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tx.category} • $formattedDate',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$sign${fmt.format(tx.amount)}',
                    style: tt.bodyMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
