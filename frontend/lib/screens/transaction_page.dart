import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/rupiah.dart';
import '../core/calendar_date.dart';
import '../core/app_state.dart';
import '../core/mock_data.dart';
import '../core/theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/section_header.dart';

// ── Formatter & helpers ───────────────────────────────────────────────────

/// Format nominal rupiah bulat tanpa desimal, misal "Rp 1.000.000".
final _currencyFmt = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');

// ── Parser nominal Indonesia ──────────────────────────────────────────────
//
// Aturan format masukan (ID):
//   Separator ribuan = titik   → "1.000"       berarti seribu
//   Separator desimal = koma   → "1.000,50"    berarti seribu lima puluh sen
//
// Parser ini MENOLAK input yang ambigu / mengandung pecahan / NaN / Infinity.
// Contoh valid  : "1500000", "1.500.000"
// Contoh ditolak: "1.500,50" (ada koma = ada pecahan → rupiah bukan bulat)
//                 "abc", ""  (non-numerik)
//                 "0"        (tidak lebih dari nol)
//                 "1.2.3"    (titik tidak konsisten sebagai ribuan)

/// Batas maksimum rupiah sesuai kontrak TransactionMapper.
const _kMaxRupiah = 9007199254740991;

/// Kembalikan nilai [double] jika [raw] adalah nominal rupiah bulat valid.
/// Lempar [FormatException] dengan pesan Indonesia jika tidak valid.
double parseRupiah(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) throw const FormatException('Jumlah wajib diisi');

  // Tolak jika ada koma (tanda desimal ID) → pasti ada pecahan
  if (trimmed.contains(',')) {
    throw const FormatException(
      'Jumlah harus bilangan bulat rupiah (tanpa sen)',
    );
  }

  // Tolak format titik ambigu: "1.2.3" atau "1.23" (bukan pemisah ribuan)
  final dotParts = trimmed.split('.');
  if (dotParts.length > 1) {
    // Setiap grup setelah titik pertama harus tepat 3 digit
    for (int i = 1; i < dotParts.length; i++) {
      if (dotParts[i].length != 3 ||
          !RegExp(r'^\d{3}$').hasMatch(dotParts[i])) {
        throw const FormatException(
          'Format tidak valid. Gunakan titik hanya sebagai pemisah ribuan '
          '(mis. 1.500.000)',
        );
      }
    }
  }

  // Hapus titik pemisah ribuan → "1.000.000" → "1000000"
  final cleaned = trimmed.replaceAll('.', '');

  // Pastikan hanya digit
  if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
    throw const FormatException(
      'Jumlah hanya boleh berisi angka dan titik pemisah ribuan',
    );
  }

  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) {
    throw const FormatException('Jumlah tidak valid');
  }
  if (value <= 0) {
    throw const FormatException('Jumlah harus lebih dari nol');
  }
  if (value > _kMaxRupiah) {
    throw const FormatException('Jumlah melebihi batas maksimum rupiah');
  }
  // Pastikan bulat
  if (value != value.roundToDouble()) {
    throw const FormatException('Jumlah harus bilangan bulat rupiah');
  }
  return value;
}

// ── TextInputFormatter: hanya izinkan digit + titik ──────────────────────
//
// Formatter MENOLAK update (kembalikan oldValue) bila ada karakter di luar
// digit dan titik. Alasan: strip diam-diam mengubah makna angka — contoh,
// paste "100,50" tanpa koma menjadi "10050" (sepuluh ribu, bukan seratus).
// Satu-satunya pengecualian adalah teks kosong (izinkan hapus semua).
//
// Untuk pengujian unit, gunakan [RupiahInputFormatter] yang diekspor
// dengan @visibleForTesting di bawah.

class _RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Izinkan hapus seluruh teks
    if (newValue.text.isEmpty) return newValue;
    // Tolak (bukan strip) jika ada karakter di luar digit dan titik.
    // Ini melindungi makna angka saat paste dari clipboard.
    if (!_kAllowedRupiah.hasMatch(newValue.text)) return oldValue;
    return newValue;
  }
}

/// Pola karakter yang diizinkan pada field nominal rupiah.
/// Hanya digit dan titik; koma, tanda negatif, dan lainnya ditolak.
final _kAllowedRupiah = RegExp(r'^[\d.]*$');

// ── Kategori (alias CategoryMeta agar ringkas) ────────────────────────────

List<CategoryMeta> _incomeCategories() =>
    CategoryMeta.knownCategories.where((c) => c.isIncome).toList();

List<CategoryMeta> _expenseCategories() =>
    CategoryMeta.knownCategories.where((c) => !c.isIncome).toList();

// ── TransactionPage ───────────────────────────────────────────────────────

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _tab.dispose();
    AppState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // ── Filtered lists ────────────────────────────────────────────────────

  List<TransactionModel> get _allTx => AppState.instance.transactions;
  List<TransactionModel> get _incomeTx =>
      AppState.instance.transactions.where((t) => t.isIncome).toList();
  List<TransactionModel> get _expenseTx =>
      AppState.instance.transactions.where((t) => !t.isIncome).toList();

  // ── Actions ───────────────────────────────────────────────────────────

  void _openAdd() {
    _showFormSheet(existing: null);
  }

  void _openEdit(TransactionModel tx) {
    _showFormSheet(existing: tx);
  }

  void _showFormSheet({required TransactionModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // tap luar (barrier) → Navigator.maybePop → PopScope di sheet.
      isDismissible: true,
      // A1-09: swipe SDK (drag-to-close) memanggil Navigator.pop imperatif
      // yang MELEWATI PopScope & bisa membuang draft tanpa keputusan.
      // Drag SDK dimatikan; swipe ditangani di _TransactionFormSheet lewat
      // _requestClose() dengan aturan clean/dirty/pending yang sama.
      enableDrag: false,
      builder: (_) => _TransactionFormSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(TransactionModel tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Hapus Transaksi?',
          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
        ),
        content: Text(
          '"${tx.description}" akan dihapus permanen dan tidak dapat dikembalikan.',
          style: GoogleFonts.lato(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Batal',
              style: GoogleFonts.lato(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Hapus',
              style: GoogleFonts.lato(
                color: AppColors.expense,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await AppState.instance.deleteTransaction(tx.id, previous: tx);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transaksi dihapus',
            style: GoogleFonts.lato(color: Colors.white),
          ),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal menghapus: $e',
            style: GoogleFonts.lato(color: Colors.white),
          ),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = AppState.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi & Akun'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openAdd,
            tooltip: 'Tambah Transaksi',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.teal,
          labelColor: AppColors.teal,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: GoogleFonts.lato(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: 'Semua'),
            Tab(text: 'Pemasukan'),
            Tab(text: 'Pengeluaran'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Ringkasan Akun (data contoh) ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Ringkasan Akun',
              style: GoogleFonts.lato(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Label data contoh — sesuai kontrak B2
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Wrap(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Data contoh • belum terhubung ke transaksi',
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: MockData.accounts.length,
              separatorBuilder: (_, a) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) => _AccountMiniCard(
                account: MockData.accounts[i],
                fmt: _currencyFmt,
              ),
            ),
          ),

          Divider(
            color: Theme.of(context).dividerColor,
            height: 20,
            indent: 16,
            endIndent: 16,
          ),

          // ── Loading / Error overlay ───────────────────────────────
          if (state.transactionsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: AppLoadingIndicator()),
            ),

          if (state.transactionsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: AppErrorState(
                message: state.transactionsError!,
                retryLabel: 'Muat Ulang',
                onRetry: () => AppState.instance.retryTransactions(),
              ),
            ),

          // ── Tab list ─────────────────────────────────────────────
          if (!state.transactionsLoading && state.transactionsError == null)
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _TxList(
                    transactions: _allTx,
                    onEdit: _openEdit,
                    onDelete: _confirmDelete,
                    emptyMessage:
                        'Belum ada transaksi.\nTambahkan transaksi pertamamu.',
                  ),
                  _TxList(
                    transactions: _incomeTx,
                    onEdit: _openEdit,
                    onDelete: _confirmDelete,
                    emptyMessage: 'Belum ada transaksi pemasukan.',
                  ),
                  _TxList(
                    transactions: _expenseTx,
                    onEdit: _openEdit,
                    onDelete: _confirmDelete,
                    emptyMessage: 'Belum ada transaksi pengeluaran.',
                  ),
                ],
              ),
            ),

          if (state.transactionsLoading || state.transactionsError != null)
            const Spacer(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        backgroundColor: AppColors.teal,
        foregroundColor: cs.onPrimary,
        icon: const Icon(Icons.add),
        label: Text(
          'Tambah',
          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ── Account Mini Card ─────────────────────────────────────────────────────

class _AccountMiniCard extends StatelessWidget {
  final AccountModel account;
  final NumberFormat fmt;

  const _AccountMiniCard({required this.account, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 155,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: account.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: account.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(account.icon, color: account.color, size: 13),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  account.name,
                  style: GoogleFonts.lato(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            fmt.format(account.balance),
            style: GoogleFonts.lato(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            account.subtitle,
            style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 9),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Transaction List ──────────────────────────────────────────────────────

class _TxList extends StatefulWidget {
  final List<TransactionModel> transactions;
  final void Function(TransactionModel) onEdit;
  final Future<void> Function(TransactionModel) onDelete;
  final String emptyMessage;

  const _TxList({
    required this.transactions,
    required this.onEdit,
    required this.onDelete,
    required this.emptyMessage,
  });

  @override
  State<_TxList> createState() => _TxListState();
}

class _TxListState extends State<_TxList> {
  // Set ID yang sedang dalam proses hapus (mencegah operasi ganda)
  final Set<String> _deleting = {};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.transactions.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Tidak Ada Transaksi',
        description: widget.emptyMessage,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: widget.transactions.length,
      separatorBuilder: (_, a) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final tx = widget.transactions[i];
        final isDeleting = _deleting.contains(tx.id);
        final sign = tx.isIncome ? '+' : '−';
        final amtColor = tx.isIncome ? AppColors.income : AppColors.expense;
        final meta = CategoryMeta.of(tx.category);

        return Dismissible(
          key: ValueKey('dismiss_${tx.id}'),
          direction: DismissDirection.endToStart,
          // Konfirmasi sebelum dismiss; return false agar Dismissible tidak
          // menghapus widget sendiri — kita kontrol melalui state AppState.
          confirmDismiss: (_) async {
            if (isDeleting) return false;
            // Panggil delete dengan konfirmasi; return false agar
            // Dismissible tidak remove widget sebelum state diperbarui.
            await _handleDelete(tx);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.delete_outline,
              color: AppColors.expense,
              size: 24,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // Ikon kategori
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 20),
                ),
                const SizedBox(width: 12),

                // Deskripsi & kategori
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx.description,
                        style: GoogleFonts.lato(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Badge kategori
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: meta.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tx.category,
                              style: GoogleFonts.lato(
                                color: meta.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _dateFmt.format(tx.date),
                            style: GoogleFonts.lato(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Nominal + tombol aksi. Flexible + scaleDown menjaga
                // nominal besar tetap utuh pada layar 320 / teks 1,5.
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$sign${_currencyFmt.rupiah(tx.amount)}',
                          style: GoogleFonts.lato(
                            color: amtColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // A1-13: target 48×48 minimum — padding diperbesar 8→16
                          Semantics(
                            label: 'Edit transaksi ${tx.description}',
                            button: true,
                            child: InkWell(
                              onTap: () => widget.onEdit(tx),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.teal,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // A1-13: target 48×48 minimum — padding diperbesar 8→16
                          Semantics(
                            label: 'Hapus transaksi ${tx.description}',
                            button: true,
                            child: InkWell(
                              onTap: isDeleting
                                  ? null
                                  : () => _handleDelete(tx),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: isDeleting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: AppColors.expense,
                                        ),
                                      )
                                    : Icon(
                                        Icons.delete_outline,
                                        color: AppColors.expense,
                                        size: 16,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDelete(TransactionModel tx) async {
    if (_deleting.contains(tx.id)) return;
    // Panggil konfirmasi di parent
    if (mounted) setState(() => _deleting.add(tx.id));
    try {
      await widget.onDelete(tx);
    } finally {
      if (mounted) setState(() => _deleting.remove(tx.id));
    }
  }
}

// ── Form Sheet ────────────────────────────────────────────────────────────

/// Kecepatan swipe-ke-bawah minimum (px/s) untuk menutup sheet.
/// Dipakai handler sendiri karena drag SDK dinonaktifkan (`enableDrag:false`)
/// agar swipe tidak melewati guard clean/dirty/pending.
const double _kSheetSwipeDismissVelocity = 250;

/// Keadaan form transaksi untuk keputusan dismissal (A1-09).
///
/// - [clean]: tidak ada perubahan tersimpan-lokal → boleh tutup tanpa tanya.
/// - [dirty]: ada perubahan yang belum disimpan → minta keputusan user.
/// - [pending]: sedang menyimpan → dismissal diblokir, tidak ada write ganda,
///   tidak menjanjikan pembatalan RPC.
enum TransactionFormDismissState { clean, dirty, pending }

class _TransactionFormSheet extends StatefulWidget {
  final TransactionModel? existing;

  const _TransactionFormSheet({required this.existing});

  @override
  State<_TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<_TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late DateTime _selectedDate;
  CategoryMeta? _selectedCategory;

  /// Kategori asal transaksi lama (dari `existing`), dipisah dari pilihan
  /// baru [_selectedCategory]. null bila bukan mode edit.
  String? _originalCategory;

  /// Jenis asal transaksi lama (`existing.isIncome`), dipisah dari pilihan
  /// baru. Tidak pernah diturunkan ulang dari kategori. null bila bukan edit.
  bool? _originalIsIncome;

  /// true setelah pengguna secara eksplisit memilih kategori di dropdown.
  bool _categoryChanged = false;

  // Anti double-submit
  bool _saving = false;
  String? _saveError;
  String? _createId;

  bool get _isEdit => widget.existing != null;

  // A14 / A1-09: tracking apakah form sudah diubah (dirty)
  bool _isDirty = false;

  // ── Snapshot baseline (nilai awal form) untuk perhitungan dirty ─────────
  // Tersimpan saat initState agar perbandingan tidak bergantung pada mutasi
  // state dan agar transaksi baru (existing == null) punya baseline eksplisit.
  late final String _initialDescription;
  late final String _initialAmount;
  late final DateTime _initialDate;

  /// Periksa apakah form berbeda dari nilai awal.
  ///
  /// A1-09: transaksi baru yang HANYA kategori atau tanggal berubah tetap
  /// dihitung dirty (selain keterangan/jumlah yang sudah dilacak).
  bool _checkDirty() {
    // Keterangan: bandingkan teks tersisa-trim terhadap baseline.
    if (_descCtrl.text.trim() != _initialDescription) return true;
    // Jumlah: bandingkan teks mentah tersisa-trim (format semantik dinilai
    // saat simpan; perubahan format pun draft yang berubah → dirty).
    if (_amountCtrl.text.trim() != _initialAmount) return true;
    // Tanggal kalender: bandingkan komponen kalender, bukan instant (R-DATE).
    final baselineDate = _isEdit ? widget.existing!.date : _initialDate;
    if (!CalendarDate.same(_selectedDate, baselineDate)) return true;
    // Kategori: hanya perubahan efektif terhadap kategori asal yang dirty.
    return _categoryDirty;
  }

  /// true bila kategori efektif berbeda dari kategori asal (baseline).
  ///
  /// Pemilihan ulang kategori yang sama tidak dihitung dirty; kategori asal
  /// tak dikenal tetap clean selama pengguna tidak memilih kategori baru.
  bool get _categoryDirty {
    if (!_categoryChanged) return false;
    final selected = _selectedCategory?.name;
    if (_isEdit) return selected != _originalCategory;
    return selected != null; // transaksi baru: null → pilihan apa pun = dirty
  }

  /// Keadaan form untuk keputusan dismissal (A1-09): clean / dirty / pending.
  TransactionFormDismissState get _dismissState {
    if (_saving) return TransactionFormDismissState.pending;
    if (_isDirty) return TransactionFormDismissState.dirty;
    return TransactionFormDismissState.clean;
  }

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    _amountCtrl = TextEditingController(
      text: ex != null ? ex.amount.toStringAsFixed(0) : '',
    );
    _selectedDate = ex?.date ?? DateTime.now();
    // Snapshot baseline SETELAH controller diisi & tanggal awal ditentukan.
    _initialDescription = (ex?.description ?? '').trim();
    _initialAmount = (ex != null ? ex.amount.toStringAsFixed(0) : '').trim();
    _initialDate = _selectedDate;
    if (ex != null) {
      // A02: kategori & jenis asal disimpan terpisah dari pilihan baru.
      _originalCategory = ex.category;
      _originalIsIncome = ex.isIncome;
      final match = CategoryMeta.knownCategories
          .where((c) => c.name == ex.category)
          .firstOrNull;
      _selectedCategory = match;
      _unknownCategory = match == null ? ex.category : null;
    }
    // A14: tandai dirty saat teks berubah
    _descCtrl.addListener(_onFieldChanged);
    _amountCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => _updateDirty();

  void _updateDirty() {
    final dirty = _checkDirty();
    if (dirty != _isDirty) setState(() => _isDirty = dirty);
  }

  // ── Dismissal (A1-09) ───────────────────────────────────────────────────

  /// Titik masuk tunggal untuk menutup form: Back, close, tap luar, swipe.
  ///
  /// - pending (`_saving`): tidak menutup; pesan eksplisit, TIDAK menjanjikan
  ///   pembatalan RPC; permintaan yang sedang berjalan tidak digandakan.
  /// - dirty: minta keputusan user (`_confirmDiscard`); draft tidak hilang
  ///   tanpa keputusan.
  /// - clean: tutup tanpa konfirmasi.
  void _requestClose() {
    if (!mounted) return;
    switch (_dismissState) {
      case TransactionFormDismissState.pending:
        _showPendingSnack();
      case TransactionFormDismissState.dirty:
        _confirmDiscard();
      case TransactionFormDismissState.clean:
        Navigator.pop(context);
    }
  }

  /// Feedback pending: bukan konfirmasi sukses, bukan klaim cancel RPC.
  void _showPendingSnack() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Penyimpanan masih berjalan. Tunggu hasil dari server; permintaan belum dibatalkan.',
        ),
      ),
    );
  }

  // A14 / A1-09: konfirmasi buang perubahan — dipanggil synchronous
  // agar tidak melanggar use_build_context_synchronously.
  void _confirmDiscard() {
    final revision = AppState.instance.sessionRevision;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: const Text('Perubahan yang belum disimpan akan hilang.'),
        actions: [
          // Cancel discard: tidak ada perubahan state → input dipertahankan.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjut Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Buang',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    ).then((shouldDiscard) {
      // Hanya discard yang disetujui menutup form; selain itu input tetap.
      if (shouldDiscard != true) return;
      if (!mounted) return;
      // Tidak melanjutkan sesi lama bila sesi berubah saat dialog terbuka.
      if (AppState.instance.sessionRevision != revision) return;
      Navigator.pop(context);
    });
  }

  /// Nama kategori dari transaksi lama yang tidak ada di daftar saat ini.
  /// null = semua dikenal.
  String? _unknownCategory;

  @override
  void dispose() {
    _descCtrl.removeListener(_onFieldChanged);
    _amountCtrl.removeListener(_onFieldChanged);
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  // ── Date picker ───────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // Rentang dinamis: 10 tahun ke belakang, 1 tahun ke depan
    final firstDate = DateTime(now.year - 10, 1, 1);
    final lastDate = DateTime(now.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(lastDate)
          ? lastDate
          : (_selectedDate.isBefore(firstDate) ? firstDate : _selectedDate),
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('id', 'ID'),
      builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _isDirty = _checkDirty();
      });
    }
  }

  // ── Kategori ──────────────────────────────────────────────────────────

  /// Jika sedang edit, semua kategori tersedia agar pengguna bisa ganti jenis.
  /// Kelompok pemasukan dan pengeluaran dipisahkan dengan divider visual.
  List<DropdownMenuItem<CategoryMeta>> _buildCategoryItems() {
    final items = <DropdownMenuItem<CategoryMeta>>[];

    void addGroup(String header, List<CategoryMeta> cats) {
      items.add(
        DropdownMenuItem<CategoryMeta>(
          enabled: false,
          value: null,
          child: Text(
            header,
            style: GoogleFonts.lato(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
      for (final c in cats) {
        items.add(
          DropdownMenuItem<CategoryMeta>(
            value: c,
            child: Row(
              children: [
                Icon(c.icon, color: c.color, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    c.name,
                    style: GoogleFonts.lato(
                      color: c.isIncome ? AppColors.income : null,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    addGroup('— PEMASUKAN —', _incomeCategories());
    addGroup('— PENGELUARAN —', _expenseCategories());
    return items;
  }

  // ── Save ──────────────────────────────────────────────────────────────

  /// true bila pengguna secara eksplisit mengganti kategori (pilihan baru)
  /// ke kategori yang berbeda dari kategori asal.
  bool get _explicitCategoryChange =>
      _categoryChanged &&
      _selectedCategory != null &&
      _selectedCategory!.name != _originalCategory;

  /// Kategori efektif saat simpan.
  ///
  /// - Perubahan kategori eksplisit → pakai pilihan baru.
  /// - Edit tanpa perubahan kategori → pertahankan kategori asal apa adanya,
  ///   termasuk kategori tak dikenal; tidak di-fallback ke pilihan pertama.
  /// - Tambah baru → pilihan kategori (wajib).
  String _effectiveCategory(CategoryMeta? picked) {
    if (_explicitCategoryChange) return picked!.name;
    final original = _originalCategory;
    if (_isEdit && original != null) return original;
    return picked!.name;
  }

  /// Jenis efektif saat simpan (pemasukan/pengeluaran).
  ///
  /// TIDAK diturunkan ulang dari kategori ketika hanya keterangan berubah.
  /// - Perubahan kategori/jenis eksplisit → jenis mengikuti pilihan baru.
  /// - Edit tanpa perubahan kategori → pertahankan `originalIsIncome`,
  ///   termasuk kategori dikenal dengan jenis legacy yang tidak selaras.
  /// - Tambah baru → jenis pilihan kategori (wajib).
  bool _effectiveIsIncome(CategoryMeta? picked) {
    if (_explicitCategoryChange) return picked!.isIncome;
    final original = _originalIsIncome;
    if (_isEdit && original != null) return original;
    return picked!.isIncome;
  }

  Future<void> _save() async {
    // A1-09: guard double-submit SINKRON di awal — pending (`_saving`) tidak
    // pernah memulai write kedua; sesi yang sedang pending tidak digandakan.
    if (_saving) return;

    setState(() => _saveError = null);

    if (!_formKey.currentState!.validate()) return;
    // A02: mode edit tanpa perubahan kategori tetap boleh disimpan —
    // kategori tak dikenal memakai kategori asal. Mode tambah baru wajib pilih.
    if (_selectedCategory == null && !(_isEdit && !_categoryChanged)) {
      setState(() => _saveError = 'Pilih kategori terlebih dahulu');
      return;
    }

    // Parse nominal dengan aturan format Indonesia
    double amount;
    try {
      amount = parseRupiah(_amountCtrl.text);
    } on FormatException catch (e) {
      setState(() => _saveError = e.message);
      return;
    }

    // A1-09 + C05/C08: snapshot sesi untuk menolak feedback sesi lama.
    final appState = AppState.instance;
    final revision = appState.sessionRevision;
    final sessionUid = appState.sessionUid;
    bool sessionActive() =>
        appState.sessionRevision == revision &&
        appState.sessionUid == sessionUid;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    try {
      final cat = _selectedCategory;
      final tx =
          widget.existing?.copyWith(
            category: _effectiveCategory(cat),
            description: _descCtrl.text.trim(),
            amount: amount,
            isIncome: _effectiveIsIncome(cat),
            date: _selectedDate,
          ) ??
          TransactionModel(
            // A1-09: createId STABIL — dibuat sekali, dipertahankan setelah
            // gagal/lost-ack agar retry tidak membuat write ganda.
            id: _createId ??= appState.generateId(),
            category: _effectiveCategory(cat),
            description: _descCtrl.text.trim(),
            amount: amount,
            isIncome: _effectiveIsIncome(cat),
            date: _selectedDate,
          );

      if (_isEdit) {
        await appState.updateTransaction(widget.existing!.id, tx);
      } else {
        await appState.addTransaction(tx);
      }

      // Tidak ada feedback sesi lama: widget dibuang ATAU sesi berubah
      // (UID switch/retry) saat permintaan berjalan.
      if (!mounted) return;
      if (!sessionActive()) {
        // Reset pending tanpa feedback sesi lama.
        setState(() => _saving = false);
        return;
      }

      Navigator.pop(context);

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Transaksi diperbarui' : 'Transaksi ditambahkan',
            // A1-12: gunakan onPrimary dari colorScheme untuk kontras di kedua tema
            style: GoogleFonts.lato(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: AppColors.teal,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Tidak ada write ganda & tidak ada feedback sesi lama. `_saving`
      // dikembalikan supaya retry (draft + createId stabil) tetap mungkin;
      // pesan error hanya ditampilkan bila sesi masih sama.
      if (sessionActive()) {
        setState(() {
          _saving = false;
          _saveError = 'Gagal menyimpan: $e';
        });
      } else {
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);

    return SafeArea(
      bottom: false,
      child: PopScope(
        // A1-09: hanya state clean yang boleh pop langsung. dirty → tanya
        // discard; pending → blokir (tidak cancel RPC, tidak ada write ganda).
        // Berlaku untuk Back, tap luar (barrier→maybePop), close, swipe.
        canPop: _dismissState == TransactionFormDismissState.clean,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _requestClose();
        },
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: mq.viewInsets.bottom + mq.padding.bottom + 16,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar + swipe-down (A1-09).
                  // SDK drag dimatikan (enableDrag:false karena melewati
                  // PopScope); swipe kami route ke _requestClose() dengan
                  // aturan clean/dirty/pending yang sama.
                  GestureDetector(
                    key: const Key('transaction-sheet-swipe-handle'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > _kSheetSwipeDismissVelocity) {
                        _requestClose();
                      }
                    },
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(
                            bottom: 12,
                            top: 4,
                            right: 48, // jangan tabrakan dengan tombol tutup
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Judul + tombol tutup eksplisit (close)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEdit ? 'Edit Transaksi' : 'Tambah Transaksi',
                          style: GoogleFonts.lato(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      // A1-09: close → _requestClose (clean/dirty/pending).
                      IconButton(
                        key: const Key('close-transaction-form'),
                        tooltip: 'Tutup',
                        icon: const Icon(Icons.close),
                        // Saat pending, tidak menutup & tidak cancel RPC.
                        onPressed: _saving ? null : _requestClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Konten bisa di-scroll
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Error banner
                          if (_saveError != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: cs.error,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _saveError!,
                                        style: GoogleFonts.lato(
                                          color: cs.onErrorContainer,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // ── Kategori ────────────────────────────────
                          Text(
                            'Kategori',
                            style: GoogleFonts.lato(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // A02: Kategori tak dikenal ditampilkan sebagai hint,
                          // tidak di-fallback diam-diam ke pilihan pertama.
                          if (_unknownCategory != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: cs.error,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Kategori "$_unknownCategory" tidak dikenal. '
                                        'Kategori asal tetap disimpan jika tidak diubah.',
                                        style: GoogleFonts.lato(
                                          color: cs.onErrorContainer,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // DropdownButtonFormField.value deprecated in 3.33+;
                          // gunakan FormField + DropdownButton untuk controlled state.
                          FormField<CategoryMeta>(
                            initialValue: _selectedCategory,
                            // A02: mode edit boleh null (kategori asal
                            // dipertahankan, termasuk kategori tak dikenal).
                            validator: (v) => v == null && !_isEdit
                                ? 'Pilih kategori terlebih dahulu'
                                : null,
                            builder: (field) {
                              return InputDecorator(
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(
                                    Icons.category_outlined,
                                  ),
                                  errorText: field.errorText,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 4,
                                  ),
                                ),
                                child: DropdownButton<CategoryMeta>(
                                  value: _selectedCategory,
                                  isExpanded: true,
                                  underline: const SizedBox.shrink(),
                                  dropdownColor: cs.surface,
                                  style: GoogleFonts.lato(
                                    color: cs.onSurface,
                                    fontSize: 13,
                                  ),
                                  hint: Text(
                                    'Pilih kategori',
                                    style: GoogleFonts.lato(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                  items: _buildCategoryItems(),
                                  onChanged: _saving
                                      ? null
                                      : (v) {
                                          if (v == null) return;
                                          setState(() {
                                            _selectedCategory = v;
                                            // Perubahan kategori eksplisit.
                                            _categoryChanged = true;
                                            _unknownCategory = null;
                                            _isDirty = _checkDirty();
                                          });
                                          field.didChange(v);
                                        },
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          // ── Keterangan ──────────────────────────────
                          TextFormField(
                            enabled: !_saving,
                            controller: _descCtrl,
                            style: GoogleFonts.lato(
                              color: cs.onSurface,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Keterangan',
                              prefixIcon: Icon(Icons.notes_outlined),
                            ),
                            // A1-03: batas selaras kontrak TransactionMapper.toMap —
                            // keterangan non-empty (min. 1 karakter non-space)
                            // & panjang ter-trim <=1000. Tidak memakai maxLength
                            // mentah agar 1001 invalid (bukan diam-diam dipotong).
                            textCapitalization: TextCapitalization.sentences,
                            // A09: Next membawa fokus ke field berikutnya
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Keterangan wajib diisi';
                              }
                              if (v.trim().length > 1000) {
                                return 'Keterangan maksimal 1000 karakter';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 14),

                          // ── Jumlah ──────────────────────────────────
                          TextFormField(
                            enabled: !_saving,
                            controller: _amountCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_RupiahInputFormatter()],
                            // A09: Done menutup keyboard setelah field terakhir
                            textInputAction: TextInputAction.done,
                            // A1-03: Done = submit; guard _saving memastikan
                            // submit ganda (Done + tap) paling banyak satu
                            // operasi; input tidak dibersihkan saat gagal.
                            onFieldSubmitted: (_) => _save(),
                            style: GoogleFonts.lato(
                              color: cs.onSurface,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Jumlah (Rp)',
                              prefixIcon: const Icon(Icons.payments_outlined),
                              helperText: 'Gunakan titik sebagai pemisah ribuan, mis. 1.500.000',
                              helperStyle: GoogleFonts.lato(fontSize: 11),
                            ),
                            validator: (v) {
                              try {
                                parseRupiah(v ?? '');
                                return null;
                              } on FormatException catch (e) {
                                return e.message;
                              }
                            },
                          ),

                          const SizedBox(height: 14),

                          // ── Tanggal ──────────────────────────────────
                          Text(
                            'Tanggal',
                            style: GoogleFonts.lato(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // A12: label aksesibilitas untuk date picker
                          Semantics(
                            label:
                                'Pilih tanggal, saat ini '
                                '${DateFormat("d MMMM yyyy", "id_ID").format(_selectedDate)}',
                            button: true,
                            child: InkWell(
                              onTap: _saving ? null : _pickDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      color: cs.onSurfaceVariant,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        DateFormat(
                                          'd MMMM yyyy',
                                          'id_ID',
                                        ).format(_selectedDate),
                                        style: GoogleFonts.lato(
                                          color: cs.onSurface,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      color: cs.onSurfaceVariant,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Tombol simpan ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEdit ? 'Simpan Perubahan' : 'Tambah Transaksi',
                              style: GoogleFonts.lato(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ), // Container
      ), // PopScope
    ); // SafeArea
  }
}
