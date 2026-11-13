import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/app_state.dart';
import '../core/csv_exporter.dart';
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
final _dateFmt = DateFormat('dd/MM/yy');

// ── Filter periode ────────────────────────────────────────────────────────

/// null = semua periode
class _PeriodFilter {
  final int? year;
  final int? month; // 1-12; null = seluruh tahun

  const _PeriodFilter({this.year, this.month});

  bool get isAll => year == null;

  String get label {
    if (isAll) return 'Semua';
    if (month == null) return '$year';
    return DateFormat('MMM yyyy', 'id_ID').format(DateTime(year!, month!));
  }

  @override
  bool operator ==(Object other) =>
      other is _PeriodFilter && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

// ── Kolom sort ────────────────────────────────────────────────────────────

enum _SortCol { no, kategori, jumlah, tanggal }

// ── DataTablePage ─────────────────────────────────────────────────────────

class DataTablePage extends StatefulWidget {
  const DataTablePage({super.key});

  @override
  State<DataTablePage> createState() => _DataTablePageState();
}

class _DataTablePageState extends State<DataTablePage> {
  _SortCol _sortCol = _SortCol.tanggal;
  bool _sortAscending = false; // default: terbaru dulu
  String _filterText = '';
  _PeriodFilter _period = const _PeriodFilter(); // semua
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // ── Derived data ──────────────────────────────────────────────────────

  /// Semua transaksi dari AppState (sumber tunggal, bukan MockData).
  List<TransactionModel> get _allTx => AppState.instance.transactions;

  /// Transaksi yang sudah difilter periode.
  List<TransactionModel> get _periodFiltered {
    if (_period.isAll) return _allTx;
    if (_period.month == null) {
      // filter seluruh tahun
      return _allTx.where((t) => t.date.year == _period.year).toList();
    }
    return FinanceSummary.filterMonth(
      _allTx,
      year: _period.year!,
      month: _period.month!,
    );
  }

  /// Transaksi setelah filter periode + pencarian teks.
  List<TransactionModel> get _displayRows {
    var rows = _periodFiltered;

    if (_filterText.isNotEmpty) {
      final q = _filterText.toLowerCase();
      rows = rows
          .where(
            (t) =>
                t.category.toLowerCase().contains(q) ||
                t.description.toLowerCase().contains(q),
          )
          .toList();
    }

    // Sort
    rows.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case _SortCol.no:
          // Nomor urut mengikuti posisi display; sort by ID stabil
          cmp = a.id.compareTo(b.id);
        case _SortCol.kategori:
          cmp = a.category.compareTo(b.category);
        case _SortCol.jumlah:
          final av = a.isIncome ? a.amount : -a.amount;
          final bv = b.isIncome ? b.amount : -b.amount;
          cmp = av.compareTo(bv);
        case _SortCol.tanggal:
          cmp = a.date.compareTo(b.date);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return rows;
  }

  // ── Ringkasan mengikuti filter aktif ──────────────────────────────────

  double get _summaryIncome => FinanceSummary.totalIncome(_periodFiltered);
  double get _summaryExpense => FinanceSummary.totalExpense(_periodFiltered);
  double get _summaryNet => FinanceSummary.netCashFlow(_periodFiltered);

  // ── Pilihan periode (bulan-bulan yang ada di data + "Semua") ──────────

  List<_PeriodFilter> _buildPeriodOptions() {
    final options = <_PeriodFilter>[const _PeriodFilter()];
    final seen = <String>{};
    for (final tx in _allTx) {
      final key = '${tx.date.year}-${tx.date.month}';
      if (seen.add(key)) {
        options.add(_PeriodFilter(year: tx.date.year, month: tx.date.month));
      }
    }
    // Urutkan: terbaru dulu
    options.sort((a, b) {
      if (a.isAll) return -1;
      if (b.isAll) return 1;
      final ay = a.year! * 12 + (a.month ?? 0);
      final by_ = b.year! * 12 + (b.month ?? 0);
      return by_.compareTo(ay);
    });
    return options;
  }

  void _sort(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAscending = !_sortAscending;
      } else {
        _sortCol = col;
        _sortAscending = col == _SortCol.kategori; // kategori default A-Z
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _filterText = '';
      _period = const _PeriodFilter();
      _sortCol = _SortCol.tanggal;
      _sortAscending = false;
      _searchCtrl.clear();
    });
  }

  Future<void> _export() async {
    if (_exporting) return;
    final rows = _displayRows;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tidak ada data untuk diekspor'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final result = await CsvExporter.export(
        transactions: rows,
        periodLabel: _period.label,
      );
      if (!mounted) return;

      if (result.isSuccess) {
        // Share sheet sudah terbuka — tidak perlu SnackBar "berhasil tersimpan"
        // karena file baru benar-benar disimpan setelah pengguna memilih tujuan.
      } else if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tidak ada transaksi untuk diekspor'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else if (result.isFailure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor: ${result.errorMessage}'),
            backgroundColor: AppColors.expense,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      // isCancelled: pengguna menutup share sheet sendiri — tidak perlu feedback
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Transaksi'),
        actions: [
          // Ekspor CSV hasil filter aktif
          _exporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.teal,
                    ),
                  ),
                )
              : Tooltip(
                  message: 'Ekspor CSV',
                  child: IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: _export,
                  ),
                ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Loading ────────────────────────────────────────────────
          if (state.transactionsLoading)
            const Expanded(
              child: AppLoadingPage(message: 'Memuat data transaksi...'),
            ),

          // ── Error ──────────────────────────────────────────────────
          if (!state.transactionsLoading && state.transactionsError != null)
            Expanded(
              child: AppErrorState(
                message: state.transactionsError!,
                retryLabel: 'Muat Ulang',
                onRetry: () => AppState.instance.retryTransactions(),
              ),
            ),

          // ── Konten utama ───────────────────────────────────────────
          if (!state.transactionsLoading && state.transactionsError == null)
            Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final rows = _displayRows;
    final periodOptions = _buildPeriodOptions();
    final hasActiveFilter = _filterText.isNotEmpty || !_period.isAll;
    final allEmpty = _allTx.isEmpty;
    final filteredEmpty = rows.isEmpty && !allEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ringkasan (mengikuti filter aktif) ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _SummaryPill(
                label: 'Pemasukan',
                value: _currencyFmt.format(_summaryIncome),
                color: AppColors.income,
              ),
              const SizedBox(width: 6),
              _SummaryPill(
                label: 'Pengeluaran',
                value: _currencyFmt.format(_summaryExpense),
                color: AppColors.expense,
              ),
              const SizedBox(width: 6),
              _SummaryPill(
                label: 'Selisih',
                value: _currencyFmt.format(_summaryNet),
                color: AppColors.teal,
              ),
            ],
          ),
        ),

        // ── Catatan ringkasan ───────────────────────────────────────
        if (!_period.isAll)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Ringkasan untuk periode: ${_period.label}',
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 10),
            ),
          ),

        const SizedBox(height: 10),

        // ── Filter bar ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Pencarian
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.lato(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Cari kategori atau keterangan...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _filterText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _filterText = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _filterText = v),
                ),
              ),
              const SizedBox(width: 8),

              // Filter periode
              _PeriodDropdown(
                options: periodOptions,
                selected: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ),
        ),

        // ── Label jumlah hasil + tombol reset ──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(
            children: [
              Text(
                allEmpty
                    ? 'Belum ada transaksi'
                    : filteredEmpty
                    ? 'Tidak ada hasil yang cocok'
                    : '${rows.length} transaksi',
                style: GoogleFonts.lato(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              if (hasActiveFilter) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _resetFilters,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.teal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_alt_off,
                          color: AppColors.teal,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reset filter',
                          style: GoogleFonts.lato(
                            color: AppColors.teal,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Tabel ──────────────────────────────────────────────────
        Expanded(
          child: allEmpty
              ? const AppEmptyState(
                  icon: Icons.table_chart_outlined,
                  title: 'Belum Ada Data',
                  description: 'Tambahkan transaksi di halaman Transaksi untuk melihat data di sini.',
                )
              : filteredEmpty
              ? AppEmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'Tidak Ada Hasil',
                  description:
                      'Tidak ada transaksi yang cocok dengan filter aktif.',
                  action: TextButton.icon(
                    onPressed: _resetFilters,
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Reset Filter'),
                  ),
                )
              : _buildTable(context, rows),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, List<TransactionModel> rows) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            // Lebar minimum agar tabel tidak terlalu sempit di layar lebar,
            // tapi tetap bisa di-scroll horizontal di layar 320.
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 32,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ───────────────────────────────────────
                  _TableHeader(
                    sortCol: _sortCol,
                    ascending: _sortAscending,
                    onSort: _sort,
                  ),

                  // ── Baris data ───────────────────────────────────
                  ...rows.asMap().entries.map((e) {
                    final idx = e.key;
                    final tx = e.value;
                    final isEven = idx % 2 == 0;
                    final signed = tx.isIncome ? tx.amount : -tx.amount;
                    final amtColor = tx.isIncome
                        ? AppColors.income
                        : AppColors.expense;
                    final sign = tx.isIncome ? '+' : '−';

                    return Container(
                      color: isEven
                          ? Colors.transparent
                          : Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.03),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          // No — mengikuti urutan tampilan
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${idx + 1}',
                              style: GoogleFonts.lato(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          // Kategori + keterangan
                          SizedBox(
                            width: 160,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx.category,
                                  style: GoogleFonts.lato(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  tx.description,
                                  style: GoogleFonts.lato(
                                    color: AppColors.textMuted,
                                    fontSize: 10,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // Jumlah
                          SizedBox(
                            width: 140,
                            child: Text(
                              '$sign${_currencyFmt.format(signed.abs())}',
                              style: GoogleFonts.lato(
                                color: amtColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Tanggal
                          SizedBox(
                            width: 70,
                            child: Text(
                              _dateFmt.format(tx.date),
                              style: GoogleFonts.lato(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // ── Footer total (dari periode terfilter) ─────────
                  _TableFooter(net: _summaryNet, periodLabel: _period.label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Period Dropdown ───────────────────────────────────────────────────────

class _PeriodDropdown extends StatelessWidget {
  final List<_PeriodFilter> options;
  final _PeriodFilter selected;
  final ValueChanged<_PeriodFilter> onChanged;

  const _PeriodDropdown({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: DropdownButton<_PeriodFilter>(
        value: selected,
        underline: const SizedBox.shrink(),
        isDense: true,
        dropdownColor: cs.surface,
        style: GoogleFonts.lato(color: cs.onSurface, fontSize: 12),
        icon: const Icon(Icons.keyboard_arrow_down, size: 16),
        items: options
            .map(
              (p) => DropdownMenuItem(
                value: p,
                child: Text(p.label, style: GoogleFonts.lato(fontSize: 12)),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// ── Table Header ──────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final _SortCol sortCol;
  final bool ascending;
  final void Function(_SortCol) onSort;

  const _TableHeader({
    required this.sortCol,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          _HeaderCell(
            label: 'No',
            width: 36,
            col: _SortCol.no,
            sortCol: sortCol,
            asc: ascending,
            onTap: onSort,
          ),
          _HeaderCell(
            label: 'Kategori',
            width: 160,
            col: _SortCol.kategori,
            sortCol: sortCol,
            asc: ascending,
            onTap: onSort,
          ),
          _HeaderCell(
            label: 'Jumlah',
            width: 140,
            col: _SortCol.jumlah,
            sortCol: sortCol,
            asc: ascending,
            onTap: onSort,
          ),
          _HeaderCell(
            label: 'Tgl',
            width: 70,
            col: _SortCol.tanggal,
            sortCol: sortCol,
            asc: ascending,
            onTap: onSort,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final _SortCol col;
  final _SortCol sortCol;
  final bool asc;
  final void Function(_SortCol) onTap;

  const _HeaderCell({
    required this.label,
    required this.width,
    required this.col,
    required this.sortCol,
    required this.asc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortCol == col;
    return GestureDetector(
      onTap: () => onTap(col),
      child: SizedBox(
        width: width,
        child: Row(
          children: [
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.lato(
                  color: isActive ? AppColors.teal : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 10,
                color: AppColors.teal,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Table Footer ──────────────────────────────────────────────────────────

class _TableFooter extends StatelessWidget {
  final double net;
  final String periodLabel;

  const _TableFooter({required this.net, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final netPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 36),
          SizedBox(
            width: 160,
            child: Text(
              'TOTAL ($periodLabel)',
              style: GoogleFonts.lato(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              '${netPositive ? '+' : '−'}${_currencyFmt.format(net.abs())}',
              style: GoogleFonts.lato(
                color: netPositive ? AppColors.income : AppColors.expense,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 70),
        ],
      ),
    );
  }
}

// ── Summary Pill ──────────────────────────────────────────────────────────

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 10),
            ),
            Text(
              value,
              style: GoogleFonts.lato(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
