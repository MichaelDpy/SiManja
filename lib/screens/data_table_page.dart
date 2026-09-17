import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/mock_data.dart';

class DataTablePage extends StatefulWidget {
  const DataTablePage({super.key});

  @override
  State<DataTablePage> createState() => _DataTablePageState();
}

class _DataTablePageState extends State<DataTablePage> {
  final _fmt =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final _dateFmt = DateFormat('dd/MM/yy');
  String _sortColumn = 'no';
  bool _sortAscending = true;
  String _filterText = '';

  List<TableRowModel> get _filteredRows {
    var rows = List<TableRowModel>.from(MockData.tableRows);
    if (_filterText.isNotEmpty) {
      rows = rows
          .where((r) =>
              r.kategori
                  .toLowerCase()
                  .contains(_filterText.toLowerCase()) ||
              r.keterangan
                  .toLowerCase()
                  .contains(_filterText.toLowerCase()))
          .toList();
    }
    rows.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'no':
          cmp = a.no.compareTo(b.no);
        case 'kategori':
          cmp = a.kategori.compareTo(b.kategori);
        case 'jumlah':
          cmp = a.jumlah.compareTo(b.jumlah);
        case 'tanggal':
          cmp = a.tanggal.compareTo(b.tanggal);
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return rows;
  }

  void _sort(String col) {
    setState(() {
      if (_sortColumn == col) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = col;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Data Transaksi'),
        actions: [
          IconButton(icon: const Icon(Icons.download_outlined), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // ── Summary pills ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _SummaryPill(
                  label: 'Pemasukan',
                  value: _fmt.format(MockData.totalIncome),
                  color: AppColors.income,
                ),
                const SizedBox(width: 8),
                _SummaryPill(
                  label: 'Pengeluaran',
                  value: _fmt.format(MockData.totalExpense),
                  color: AppColors.expense,
                ),
                const SizedBox(width: 8),
                _SummaryPill(
                  label: 'Selisih',
                  value: _fmt.format(MockData.netBalance),
                  color: AppColors.teal,
                ),
              ],
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              style:
                  GoogleFonts.lato(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Cari kategori atau keterangan...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _filterText = v),
            ),
          ),

          // ── Table ─────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: const BoxDecoration(
                        color: AppColors.bgCardAlt,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          _HeaderCell(
                            label: 'No',
                            flex: 1,
                            col: 'no',
                            sortCol: _sortColumn,
                            asc: _sortAscending,
                            onTap: _sort,
                          ),
                          _HeaderCell(
                            label: 'Kategori',
                            flex: 3,
                            col: 'kategori',
                            sortCol: _sortColumn,
                            asc: _sortAscending,
                            onTap: _sort,
                          ),
                          _HeaderCell(
                            label: 'Jumlah',
                            flex: 3,
                            col: 'jumlah',
                            sortCol: _sortColumn,
                            asc: _sortAscending,
                            onTap: _sort,
                          ),
                          _HeaderCell(
                            label: 'Tgl',
                            flex: 2,
                            col: 'tanggal',
                            sortCol: _sortColumn,
                            asc: _sortAscending,
                            onTap: _sort,
                          ),
                        ],
                      ),
                    ),

                    // Rows
                    ...rows.asMap().entries.map((e) {
                      final r = e.value;
                      final isEven = e.key % 2 == 0;
                      final isPositive = r.jumlah >= 0;
                      return Container(
                        color: isEven
                            ? Colors.transparent
                            : AppColors.bgCardAlt.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 11),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${r.no}',
                                style: GoogleFonts.lato(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.kategori,
                                    style: GoogleFonts.lato(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    r.keterangan,
                                    style: GoogleFonts.lato(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${isPositive ? '+' : ''}${_fmt.format(r.jumlah)}',
                                style: GoogleFonts.lato(
                                  color: isPositive
                                      ? AppColors.income
                                      : AppColors.expense,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _dateFmt.format(r.tanggal),
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

                    // Footer total
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.bgCardAlt,
                        borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(flex: 1, child: SizedBox()),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'TOTAL',
                              style: GoogleFonts.lato(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              _fmt.format(MockData.netBalance),
                              style: GoogleFonts.lato(
                                color: AppColors.teal,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Expanded(flex: 2, child: SizedBox()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  final String col;
  final String sortCol;
  final bool asc;
  final void Function(String) onTap;

  const _HeaderCell({
    required this.label,
    required this.flex,
    required this.col,
    required this.sortCol,
    required this.asc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = sortCol == col;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => onTap(col),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.lato(
                color:
                    isActive ? AppColors.teal : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
