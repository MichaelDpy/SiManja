import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';

/// Utilitas perhitungan dan filter untuk halaman Aset SIMANJA.
///
/// Logika murni agar dapat diuji secara terisolasi tanpa dependensi UI.
class AssetCalculator {
  AssetCalculator._();

  /// Hitung total nilai aset dari daftar [items]. Tangani daftar kosong.
  static double calculateTotal(List<AssetModel> items) {
    if (items.isEmpty) return 0.0;
    return items.fold<double>(0.0, (sum, a) => sum + a.value);
  }

  /// Hitung persentase nilai [value] dari [total].
  ///
  /// Kembalikan 0.0 bila [total] <= 0 atau [value] <= 0 (mencegah NaN / Infinity).
  static double calculatePercentage(double value, double total) {
    if (total <= 0 || value <= 0) return 0.0;
    return (value / total) * 100.0;
  }

  /// Filter daftar aset berdasarkan [category].
  ///
  /// Jika [category] bernilai null, kosong, atau 'Semua', kembalikan seluruh aset.
  static List<AssetModel> filterByCategory(
    List<AssetModel> items,
    String? category,
  ) {
    if (category == null || category.isEmpty || category == 'Semua') {
      return List<AssetModel>.unmodifiable(items);
    }
    return items.where((a) => a.name == category).toList();
  }

  /// Dapatkan label judul cakupan total yang menjelaskan filter aktif.
  static String getScopeLabel(String? category) {
    if (category == null || category.isEmpty || category == 'Semua') {
      return 'Total Nilai Aset (Semua Kategori)';
    }
    return 'Total Nilai Aset ($category)';
  }

  /// Dapatkan teks subjudul cakupan.
  static String getScopeSubtitle(int count, String? category) {
    if (category == null || category.isEmpty || category == 'Semua') {
      return 'Mencakup $count kategori aset contoh';
    }
    return 'Kategori: $category • $count aset';
  }
}

class AssetPage extends StatefulWidget {
  const AssetPage({super.key});

  @override
  State<AssetPage> createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  int _touchedIndex = -1;
  String? _selectedCategory; // null = Semua kategori

  final _fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory =
          (category == null || category == 'Semua') ? null : category;
      _touchedIndex = -1;
    });
  }

  void _resetFilter() {
    _selectCategory(null);
  }

  void _showFilterModal(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filter Kategori Aset',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_selectedCategory != null)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _resetFilter();
                        },
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.dashboard_customize_outlined,
                    color: _selectedCategory == null
                        ? AppColors.teal
                        : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    'Semua Kategori (${MockData.assets.length})',
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: _selectedCategory == null
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: _selectedCategory == null
                      ? const Icon(Icons.check, color: AppColors.teal)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _resetFilter();
                  },
                ),
                const Divider(),
                ...MockData.assets.map((asset) {
                  final isSelected = _selectedCategory == asset.name;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: asset.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      asset.name,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      _fmt.format(asset.value),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.teal)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _selectCategory(asset.name);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // Filter data aset
    final filteredAssets = AssetCalculator.filterByCategory(
      MockData.assets,
      _selectedCategory,
    );
    final total = AssetCalculator.calculateTotal(filteredAssets);

    // Amankan index sentuh agar tidak out of bounds setelah filter
    final safeTouchedIndex =
        (_touchedIndex >= 0 && _touchedIndex < filteredAssets.length)
            ? _touchedIndex
            : -1;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Ringkasan Aset'),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter kategori aset',
                onPressed: () => _showFilterModal(context),
              ),
              if (_selectedCategory != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;

              final totalCard = _buildTotalCard(
                context,
                total: total,
                category: _selectedCategory,
                count: filteredAssets.length,
              );

              final filterBar = _buildFilterBar(context);

              final donutCard = _buildDonutCard(
                context,
                assets: filteredAssets,
                total: total,
                touchedIndex: safeTouchedIndex,
                maxWidth: isWide
                    ? (constraints.maxWidth - 20) / 2
                    : constraints.maxWidth,
              );

              final detailList = _buildDetailList(
                context,
                assets: filteredAssets,
                total: total,
              );

              if (isWide) {
                // Layout 2 kolom untuk landscape / layar lebar
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          totalCard,
                          const SizedBox(height: 16),
                          donutCard,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          filterBar,
                          const SizedBox(height: 16),
                          detailList,
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Layout 1 kolom vertikal untuk portrait
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  totalCard,
                  const SizedBox(height: 16),
                  filterBar,
                  const SizedBox(height: 16),
                  donutCard,
                  const SizedBox(height: 20),
                  detailList,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Kartu Total Nilai Aset ─────────────────────────────────────────────────

  Widget _buildTotalCard(
    BuildContext context, {
    required double total,
    required String? category,
    required int count,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final scopeLabel = AssetCalculator.getScopeLabel(category);
    final scopeSubtitle = AssetCalculator.getScopeSubtitle(count, category);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          // Badge data contoh & belum tersinkron
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Data contoh • belum tersinkron dengan transaksi',
              style: GoogleFonts.lato(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            scopeLabel,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _fmt.format(total),
              style: tt.headlineMedium?.copyWith(
                color: AppColors.teal,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            scopeSubtitle,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Bar Filter Kategori Aset ───────────────────────────────────────────────

  Widget _buildFilterBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // Chip Semua
              ChoiceChip(
                label: Text('Semua (${MockData.assets.length})'),
                selected: _selectedCategory == null,
                onSelected: (_) => _resetFilter(),
                labelStyle: GoogleFonts.lato(
                  fontSize: 11,
                  fontWeight: _selectedCategory == null
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _selectedCategory == null ? Colors.white : cs.onSurface,
                ),
                selectedColor: AppColors.teal,
                backgroundColor: cs.surface,
                side: BorderSide(
                  color: _selectedCategory == null
                      ? AppColors.teal
                      : cs.outline.withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              const SizedBox(width: 8),
              // Chips untuk setiap kategori aset
              ...MockData.assets.map((asset) {
                final isSelected = _selectedCategory == asset.name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: asset.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    label: Text(asset.name),
                    selected: isSelected,
                    onSelected: (_) => _selectCategory(asset.name),
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
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // ── Kartu Diagram Donut Distribusi Portofolio ──────────────────────────────

  Widget _buildDonutCard(
    BuildContext context, {
    required List<AssetModel> assets,
    required double total,
    required int touchedIndex,
    required double maxWidth,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    // Hitung label dan nilai di tengah diagram
    final touchedAsset =
        (touchedIndex >= 0 && touchedIndex < assets.length)
            ? assets[touchedIndex]
            : null;

    final centerLabel = touchedAsset != null
        ? touchedAsset.name
        : (_selectedCategory != null ? _selectedCategory! : 'Total');

    final centerValue = touchedAsset != null
        ? _fmt.format(touchedAsset.value)
        : _fmt.format(total);

    final centerPercentage = (touchedAsset != null && total > 0)
        ? '${AssetCalculator.calculatePercentage(touchedAsset.value, total).toStringAsFixed(1)}%'
        : null;

    // Skala dimensi chart agar aman dari overflow pada layar 320 dp
    final isCompact = maxWidth < 340;
    final centerSpaceRadius = isCompact ? 46.0 : 56.0;
    final normalRadius = isCompact ? 46.0 : 62.0;
    final touchedRadius = isCompact ? 56.0 : 74.0;
    final chartHeight = isCompact ? 220.0 : 250.0;

    return Container(
      width: double.infinity,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Distribusi Portofolio',
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_selectedCategory != null)
                TextButton.icon(
                  onPressed: _resetFilter,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(40, 30),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Tangani kondisi total nol atau daftar kosong tanpa crash
          if (assets.isEmpty || total <= 0)
            Container(
              height: 200,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 48,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tidak ada data aset untuk ditampilkan',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resetFilter,
                    child: const Text('Kembali ke Semua Aset'),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: chartHeight,
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
                      sections: assets.asMap().entries.map((e) {
                        final idx = e.key;
                        final asset = e.value;
                        final isTouched = idx == touchedIndex;
                        final pct = AssetCalculator.calculatePercentage(
                          asset.value,
                          total,
                        );

                        return PieChartSectionData(
                          value: asset.value,
                          color: asset.color,
                          radius: isTouched ? touchedRadius : normalRadius,
                          title: isTouched
                              ? '${pct.toStringAsFixed(1)}%'
                              : '',
                          titleStyle: GoogleFonts.lato(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                      centerSpaceRadius: centerSpaceRadius,
                      sectionsSpace: 2.5,
                    ),
                  ),
                  // Label tengah aman tidak overflow lingkaran donat
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: centerSpaceRadius * 1.8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          centerLabel,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            centerValue,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (centerPercentage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            centerPercentage,
                            style: GoogleFonts.lato(
                              color: AppColors.teal,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Daftar Detail Aset ─────────────────────────────────────────────────────

  Widget _buildDetailList(
    BuildContext context, {
    required List<AssetModel> assets,
    required double total,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Detail Aset',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${assets.length} Aset',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (assets.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.filter_alt_off_outlined,
                  size: 40,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tidak ada data aset untuk filter ini',
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pilih kategori lain atau reset filter.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _resetFilter,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Tampilkan Semua Aset'),
                ),
              ],
            ),
          )
        else
          ...assets.map(
            (a) => _AssetDetailCard(
              asset: a,
              total: total,
              fmt: _fmt,
              onTap: () => _selectCategory(a.name),
            ),
          ),
      ],
    );
  }
}

// ── Widget Kartu Detail Aset ─────────────────────────────────────────────────

class _AssetDetailCard extends StatelessWidget {
  final AssetModel asset;
  final double total;
  final NumberFormat fmt;
  final VoidCallback? onTap;

  const _AssetDetailCard({
    required this.asset,
    required this.total,
    required this.fmt,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final percentage = AssetCalculator.calculatePercentage(asset.value, total);
    final progress = total > 0 ? (asset.value / total).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.3),
            ),
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
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${percentage.toStringAsFixed(1)}% dari total',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        fmt.format(asset.value),
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: cs.outline.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(asset.color),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),
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
