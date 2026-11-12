import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

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
// Contoh valid  : "1500000", "1.500.000", "1500000"
// Contoh ditolak: "1.500,50" (ada koma = ada pecahan → rupiah bukan bulat)
//                 "abc", ""  (non-numerik)
//                 "0"        (tidak lebih dari nol)

/// Kembalikan nilai [double] jika [raw] adalah nominal rupiah bulat valid.
/// Lempar [FormatException] dengan pesan Indonesia jika tidak valid.
double parseRupiah(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) throw FormatException('Jumlah wajib diisi');

  // Tolak jika ada koma (tanda desimal ID) → pasti ada pecahan
  if (trimmed.contains(',')) {
    throw FormatException('Jumlah harus bilangan bulat rupiah (tanpa sen)');
  }

  // Hapus titik pemisah ribuan → "1.000.000" → "1000000"
  final cleaned = trimmed.replaceAll('.', '');

  // Pastikan hanya digit
  if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
    throw FormatException('Jumlah hanya boleh berisi angka dan titik pemisah');
  }

  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite) {
    throw FormatException('Jumlah tidak valid');
  }
  if (value <= 0) {
    throw FormatException('Jumlah harus lebih dari nol');
  }
  // Pastikan bulat (seharusnya sudah karena cleaned hanya digit, tapi jaga-jaga)
  if (value != value.roundToDouble()) {
    throw FormatException('Jumlah harus bilangan bulat rupiah');
  }
  return value;
}

// ── TextInputFormatter: hanya izinkan digit + titik ──────────────────────

class _RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Izinkan hapus seluruh teks
    if (newValue.text.isEmpty) return newValue;
    // Hanya digit dan titik
    final filtered = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    if (filtered != newValue.text) {
      return newValue.copyWith(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }
    return newValue;
  }
}

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
      await AppState.instance.deleteTransaction(tx.id);
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
            child: Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    title: 'Ringkasan Akun',
                    actionLabel: 'Kelola',
                    onAction: () {},
                  ),
                ),
              ],
            ),
          ),
          // Label data contoh — sesuai kontrak B2
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Row(
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

                // Nominal + tombol aksi
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$sign${_currencyFmt.format(tx.amount)}',
                      style: GoogleFonts.lato(
                        color: amtColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tombol edit — mudah ditemukan tanpa long press
                        InkWell(
                          onTap: () => widget.onEdit(tx),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit_outlined,
                              color: AppColors.teal,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Tombol hapus
                        InkWell(
                          onTap: isDeleting ? null : () => _handleDelete(tx),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
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
                      ],
                    ),
                  ],
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

  // Anti double-submit
  bool _saving = false;
  String? _saveError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    // Tampilkan angka tanpa separator saat edit agar parser tidak bingung
    _amountCtrl = TextEditingController(
      text: ex != null ? ex.amount.toStringAsFixed(0) : '',
    );
    _selectedDate = ex?.date ?? DateTime.now();
    if (ex != null) {
      _selectedCategory = CategoryMeta.knownCategories.firstWhere(
        (c) => c.name == ex.category,
        orElse: () => CategoryMeta.knownCategories.first,
      );
    }
  }

  @override
  void dispose() {
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
    if (picked != null && mounted) setState(() => _selectedDate = picked);
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

  Future<void> _save() async {
    setState(() => _saveError = null);

    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
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

    if (_saving) return; // guard double-submit
    setState(() => _saving = true);

    try {
      final cat = _selectedCategory!;
      final tx = TransactionModel(
        id: widget.existing?.id ?? AppState.instance.generateId(),
        category: cat.name,
        description: _descCtrl.text.trim(),
        amount: amount,
        isIncome: cat.isIncome,
        date: _selectedDate,
      );

      if (_isEdit) {
        await AppState.instance.updateTransaction(widget.existing!.id, tx);
      } else {
        await AppState.instance.addTransaction(tx);
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Transaksi diperbarui' : 'Transaksi ditambahkan',
            style: GoogleFonts.lato(color: Colors.white),
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
      setState(() {
        _saving = false;
        _saveError = 'Gagal menyimpan: $e';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);

    return SafeArea(
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Tinggi max: 92% layar; min: sisakan ruang keyboard
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
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Judul
                Row(
                  children: [
                    Text(
                      _isEdit ? 'Edit Transaksi' : 'Tambah Transaksi',
                      style: GoogleFonts.lato(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
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
                        // DropdownButtonFormField.value deprecated in 3.33+;
                        // gunakan FormField + DropdownButton untuk controlled state.
                        FormField<CategoryMeta>(
                          initialValue: _selectedCategory,
                          validator: (v) => v == null
                              ? 'Pilih kategori terlebih dahulu'
                              : null,
                          builder: (field) {
                            return InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.category_outlined),
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
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _selectedCategory = v);
                                  field.didChange(v);
                                },
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 14),

                        // ── Keterangan ──────────────────────────────
                        TextFormField(
                          controller: _descCtrl,
                          style: GoogleFonts.lato(
                            color: cs.onSurface,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Keterangan',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                          maxLength: 120,
                          textCapitalization: TextCapitalization.sentences,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Keterangan wajib diisi';
                            }
                            if (v.trim().length < 3) {
                              return 'Keterangan terlalu pendek';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 14),

                        // ── Jumlah ──────────────────────────────────
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_RupiahInputFormatter()],
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
                        InkWell(
                          onTap: _pickDate,
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
      ),
    );
  }
}
