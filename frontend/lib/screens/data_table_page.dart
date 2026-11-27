import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/rupiah.dart';
import '../core/app_state.dart';
import '../core/csv_exporter.dart';
import '../core/report_controller.dart';
import '../core/transaction_report.dart';
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
  late final ReportController _report;

  @override
  void initState() {
    super.initState();
    _report = ReportController(AppState.instance)
      ..addListener(_onReportChanged);
    AppState.instance.addListener(_onStateChanged);
  }

  void _onReportChanged() {
    if (mounted) setState(() {});
  }

  void _configureReport() => _report.configure(
    ReportCriteria(
      from: _period.isAll ? null : DateTime(_period.year!, _period.month ?? 1),
      until: _period.isAll
          ? null
          : _period.month == null
          ? DateTime(_period.year! + 1)
          : DateTime(_period.year!, _period.month! + 1),
      search: _filterText,
      sort: switch (_sortCol) {
        _SortCol.no => ReportSort.number,
        _SortCol.kategori => ReportSort.category,
        _SortCol.jumlah => ReportSort.amount,
        _SortCol.tanggal => ReportSort.date,
      },
      ascending: _sortAscending,
    ),
  );

  void _onStateChanged() {
    if (mounted) {
      // A05: jaga invariant — jika bulan terpilih tidak ada lagi di data,
      // reset ke "Semua" agar DropdownButton tidak menerima value tak dikenal.
      final opts = _buildPeriodOptions();
      if (!opts.contains(_period)) {
        _period = const _PeriodFilter();
      }
      _configureReport();
      setState(() {});
    }
  }

  // ── Derived data ──────────────────────────────────────────────────────

  /// Semua transaksi dari AppState (sumber tunggal, bukan MockData).
  List<TransactionModel> get _allTx => AppState.instance.transactions;

  /// Complete matching selection, independently of the visible table page.
  List<TransactionModel> get _displayRows => _report.report.rows;

  // ── Ringkasan mengikuti filter aktif ──────────────────────────────────

  BigInt get _summaryIncome => _report.report.income;
  BigInt get _summaryExpense => _report.report.expense;
  BigInt get _summaryNet => _report.report.net;

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
    _configureReport();
  }

  void _resetFilters() {
    setState(() {
      _filterText = '';
      _period = const _PeriodFilter();
      _sortCol = _SortCol.tanggal;
      _sortAscending = false;
      _searchCtrl.clear();
    });
    _configureReport();
  }

  Future<void> _export() async {
    if (_exporting || !_report.report.source.canExport) return;
    // A08: Bekukan snapshot saat ekspor dimulai — perubahan stream setelah
    // ini tidak masuk ke file yang sedang dibuat.
    final captured = _report.captureExport();
    final snapshot = captured.rows;
    final snapshotPeriod = _period.label;
    final snapshotSearch = _filterText.trim();
    final snapshotUid = AppState.instance.sessionUid;
    final snapshotRevision = AppState.instance.sessionRevision;
    final snapshotLease = AppState.instance.exportLease;
    bool isCurrent() =>
        mounted &&
        AppState.instance.sessionUid == snapshotUid &&
        AppState.instance.sessionRevision == snapshotRevision;

    if (snapshot.isEmpty) {
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
        transactions: snapshot,
        periodLabel: snapshotPeriod,
        search: snapshotSearch,
        isCurrent: isCurrent,
        lease: snapshotLease,
      );
      // A08: Periksa UID tidak berubah selama ekspor berlangsung
      if (!mounted) return;
      if (!isCurrent()) {
        // Sesi berubah — abaikan hasil tanpa menampilkan sukses
        return;
      }

      if (result.isSuccess) {
        // Share sheet sudah terbuka — tidak klaim "berhasil tersimpan"
        // karena file baru tersimpan setelah pengguna memilih tujuan.
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
      // isCancelled: pengguna menutup share sheet — tidak perlu feedback
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    _report.removeListener(_onReportChanged);
    _report.dispose();
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
                    onPressed: _report.report.source.canExport ? _export : null,
                  ),
                ),
          IconButton(
            key: const Key('report-reload'),
            tooltip: 'Muat ulang laporan',
            onPressed: state.transactionsLoading
                ? null
                : state.retryTransactions,
            icon: const Icon(Icons.refresh),
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
    final rows = _report.visibleRows;
    final periodOptions = _buildPeriodOptions();
    final hasActiveFilter = _filterText.isNotEmpty || !_period.isAll;
    final allEmpty = _allTx.isEmpty;
    final filteredEmpty = rows.isEmpty && !allEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_report.report.source.canExport)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _report.report.source.fromCache
                  ? 'Data dari cache. Ringkasan belum dipastikan lengkap; tunggu konfirmasi server untuk ekspor.'
                  : 'Menunggu konfirmasi data. Ekspor tersedia setelah laporan lengkap dimuat.',
              key: const Key('report-completeness'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        if (_report.loadingPage) const LinearProgressIndicator(minHeight: 2),
        if (_report.pageNotice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              _report.pageNotice!,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        // ── Ringkasan (mengikuti filter aktif) ─────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _SummaryPill(
                label: 'Pemasukan',
                value: _currencyFmt.rupiah(_summaryIncome),
                color: AppColors.income,
              ),
              const SizedBox(width: 6),
              _SummaryPill(
                label: 'Pengeluaran',
                value: _currencyFmt.rupiah(_summaryExpense),
                color: AppColors.expense,
              ),
              const SizedBox(width: 6),
              _SummaryPill(
                label: 'Selisih',
                value: _currencyFmt.rupiah(_summaryNet),
                color: AppColors.teal,
              ),
            ],
          ),
        ),

        // ── Catatan ringkasan ───────────────────────────────────────
        if (!_period.isAll || _filterText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              // A06: label scope menjelaskan angka mana yang ditampilkan
              _filterText.isNotEmpty && !_period.isAll
                  ? 'Ringkasan untuk periode "${_period.label}", '
                        'pencarian "$_filterText" — ${_displayRows.length} transaksi'
                  : _filterText.isNotEmpty
                  ? 'Ringkasan untuk pencarian "$_filterText" — '
                        '${_displayRows.length} dari ${_allTx.length} transaksi'
                  : 'Ringkasan untuk periode: ${_period.label}',
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 10),
            ),
          ),

        const SizedBox(height: 10),

        // ── Filter bar ──────────────────────────────────────────────
        Padding(
          key: const ValueKey('report-filter-bar'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Pencarian
              Expanded(
                child: TextField(
                  key: const ValueKey('report-search'),
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
                              _configureReport();
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    setState(() => _filterText = v);
                    _configureReport();
                  },
                ),
              ),
              const SizedBox(width: 8),

              // Filter periode
              _PeriodDropdown(
                options: periodOptions,
                // A05: jika _period tidak ada di opsi (bulan terhapus dari data),
                // fallback ke "Semua" agar tidak ada assertion DropdownButton.
                selected: periodOptions.contains(_period)
                    ? _period
                    : const _PeriodFilter(),
                onChanged: (p) {
                  setState(() => _period = p);
                  _configureReport();
                },
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
                    : '${_displayRows.length} transaksi',
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
        if (_displayRows.length > _report.pageSize)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    '${_report.firstRow}–${_report.lastRow} dari ${_displayRows.length} transaksi',
                    key: const Key('report-page-range'),
                  ),
                  IconButton(
                    key: const Key('report-previous'),
                    tooltip: 'Halaman sebelumnya',
                    onPressed: _report.hasPrevious
                        ? _report.previousPage
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('report-next'),
                    tooltip: 'Halaman berikutnya',
                    onPressed: _report.hasNext ? _report.nextPage : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, List<TransactionModel> rows) {
    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              // Lebar pasti: scroll horizontal memberi constraint tak terbatas.
              // 430 = kolom 36 + 160 + 140 + 70, ditambah padding 24.
              constraints: BoxConstraints(
                minWidth: (constraints.maxWidth - 32).clamp(
                  430.0,
                  double.infinity,
                ),
                maxWidth: (constraints.maxWidth - 32).clamp(
                  430.0,
                  double.infinity,
                ),
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
                                '${_report.firstRow + idx}',
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
                                '$sign${_currencyFmt.rupiah(signed.abs())}',
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
                    _TableFooter(
                      net: _summaryNet,
                      periodLabel:
                          '${_period.label}${_filterText.trim().isEmpty ? '' : '; hasil pencarian'}',
                    ),
                  ],
                ),
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
  final BigInt net;
  final String periodLabel;

  const _TableFooter({required this.net, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    final netPositive = net >= BigInt.zero;
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
              '${netPositive ? '+' : '−'}${_currencyFmt.rupiah(net.abs())}',
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
