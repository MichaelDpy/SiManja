import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';
import '../core/app_state.dart';
import '../widgets/section_header.dart';

// ── Kategori yang tersedia ────────────────────────────────────────────────
class _CategoryOption {
  final String name;
  final IconData icon;
  final Color color;
  final bool isIncome;

  const _CategoryOption({
    required this.name,
    required this.icon,
    required this.color,
    required this.isIncome,
  });
}

const List<_CategoryOption> _kCategories = [
  _CategoryOption(
    name: 'Gaji',
    icon: Icons.work,
    color: AppColors.income,
    isIncome: true,
  ),
  _CategoryOption(
    name: 'Transfer Masuk',
    icon: Icons.swap_horiz,
    color: AppColors.income,
    isIncome: true,
  ),
  _CategoryOption(
    name: 'Investasi Masuk',
    icon: Icons.trending_up,
    color: AppColors.income,
    isIncome: true,
  ),
  _CategoryOption(
    name: 'Lainnya (Masuk)',
    icon: Icons.add_circle_outline,
    color: AppColors.income,
    isIncome: true,
  ),
  _CategoryOption(
    name: 'Makan & Minum',
    icon: Icons.restaurant,
    color: AppColors.chart3,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Transportasi',
    icon: Icons.directions_car,
    color: AppColors.chart2,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Tagihan',
    icon: Icons.bolt,
    color: AppColors.chart6,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Kesehatan',
    icon: Icons.local_hospital,
    color: AppColors.chart4,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Investasi',
    icon: Icons.trending_up,
    color: AppColors.teal,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Hiburan',
    icon: Icons.movie,
    color: AppColors.chart4,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Pendidikan',
    icon: Icons.school,
    color: AppColors.chart5,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Belanja',
    icon: Icons.shopping_bag,
    color: AppColors.chart3,
    isIncome: false,
  ),
  _CategoryOption(
    name: 'Lainnya (Keluar)',
    icon: Icons.remove_circle_outline,
    color: AppColors.expense,
    isIncome: false,
  ),
];

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _dateFmt = DateFormat('d MMM yyyy', 'id_ID');

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

  List<TransactionModel> get _allTx => AppState.instance.transactions;
  List<TransactionModel> get _incomeTx =>
      AppState.instance.transactions.where((t) => t.isIncome).toList();
  List<TransactionModel> get _expenseTx =>
      AppState.instance.transactions.where((t) => !t.isIncome).toList();

  void _openAddDialog() {
    _showTxDialog(context, existing: null, existingIndex: null);
  }

  void _openEditDialog(TransactionModel tx, int index) {
    _showTxDialog(context, existing: tx, existingIndex: index);
  }

  void _confirmDelete(TransactionModel tx) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(
          'Hapus Transaksi?',
          style: GoogleFonts.lato(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Transaksi "${tx.description}" akan dihapus permanen.',
          style: GoogleFonts.lato(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: GoogleFonts.lato(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              AppState.instance.deleteTransaction(tx.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Transaksi dihapus',
                    style: GoogleFonts.lato(color: AppColors.bgDark),
                  ),
                  backgroundColor: AppColors.expense,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
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
  }

  void _showTxDialog(
    BuildContext ctx, {
    required TransactionModel? existing,
    required int? existingIndex,
  }) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TransactionFormSheet(
        existing: existing,
        existingIndex: existingIndex,
        onSaved: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Transaksi & Akun'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openAddDialog,
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
        children: [
          // ── Account Cards ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SectionHeader(
              title: 'Ringkasan Akun',
              actionLabel: 'Kelola',
              onAction: () {},
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: MockData.accounts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) =>
                  _AccountMiniCard(account: MockData.accounts[i], fmt: _fmt),
            ),
          ),

          const SizedBox(height: 4),

          const Divider(
            color: AppColors.divider,
            height: 24,
            indent: 16,
            endIndent: 16,
          ),

          // ── Transactions ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TxList(
                  transactions: _allTx,
                  fmt: _fmt,
                  dateFmt: _dateFmt,
                  onEdit: _openEditDialog,
                  onDelete: _confirmDelete,
                ),
                _TxList(
                  transactions: _incomeTx,
                  fmt: _fmt,
                  dateFmt: _dateFmt,
                  onEdit: _openEditDialog,
                  onDelete: _confirmDelete,
                ),
                _TxList(
                  transactions: _expenseTx,
                  fmt: _fmt,
                  dateFmt: _dateFmt,
                  onEdit: _openEditDialog,
                  onDelete: _confirmDelete,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.bgDark,
        icon: const Icon(Icons.add),
        label: Text(
          'Tambah Transaksi',
          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ── Form Sheet Tambah/Edit ────────────────────────────────────────────────
class _TransactionFormSheet extends StatefulWidget {
  final TransactionModel? existing;
  final int? existingIndex;
  final VoidCallback onSaved;

  const _TransactionFormSheet({
    required this.existing,
    required this.existingIndex,
    required this.onSaved,
  });

  @override
  State<_TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<_TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _amountCtrl;
  late DateTime _selectedDate;
  _CategoryOption? _selectedCategory;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _descCtrl = TextEditingController(text: ex?.description ?? '');
    _amountCtrl = TextEditingController(
      text: ex != null ? ex.amount.toStringAsFixed(0) : '',
    );
    _selectedDate = ex?.date ?? DateTime.now();

    if (ex != null) {
      _selectedCategory = _kCategories.firstWhere(
        (c) => c.name == ex.category,
        orElse: () => _kCategories.first,
      );
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.teal,
            surface: AppColors.bgCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pilih kategori terlebih dahulu',
            style: GoogleFonts.lato(color: AppColors.bgDark),
          ),
          backgroundColor: AppColors.expense,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final cat = _selectedCategory!;
    final tx = TransactionModel(
      id: widget.existing?.id ?? AppState.instance.generateId(),
      category: cat.name,
      description: _descCtrl.text.trim(),
      amount: double.parse(
        _amountCtrl.text.replaceAll(',', '').replaceAll('.', ''),
      ),
      isIncome: cat.isIncome,
      date: _selectedDate,
      icon: cat.icon,
      color: cat.color,
    );

    if (widget.existingIndex != null) {
      AppState.instance.updateTransaction(widget.existingIndex!, tx);
    } else {
      AppState.instance.addTransaction(tx);
    }

    Navigator.pop(context);
    widget.onSaved();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.existing != null
              ? 'Transaksi diperbarui'
              : 'Transaksi ditambahkan',
          style: GoogleFonts.lato(color: AppColors.bgDark),
        ),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? 'Edit Transaksi' : 'Tambah Transaksi',
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // Kategori
              Text(
                'Kategori',
                style: GoogleFonts.lato(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: DropdownButtonFormField<_CategoryOption>(
                  value: _selectedCategory,
                  dropdownColor: AppColors.bgCard,
                  style: GoogleFonts.lato(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  hint: Text(
                    'Pilih kategori',
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  items: _kCategories.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(c.icon, color: c.color, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            c.name,
                            style: GoogleFonts.lato(
                              color: c.isIncome
                                  ? AppColors.income
                                  : AppColors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v),
                ),
              ),

              const SizedBox(height: 14),

              // Deskripsi
              TextFormField(
                controller: _descCtrl,
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  prefixIcon: Icon(Icons.notes),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Keterangan wajib diisi'
                    : null,
              ),

              const SizedBox(height: 14),

              // Jumlah
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  labelText: 'Jumlah (Rp)',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Jumlah wajib diisi';
                  final cleaned = v.replaceAll(',', '').replaceAll('.', '');
                  if (double.tryParse(cleaned) == null)
                    return 'Format tidak valid';
                  if (double.parse(cleaned) <= 0)
                    return 'Jumlah harus lebih dari 0';
                  return null;
                },
              ),

              const SizedBox(height: 14),

              // Tanggal
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat(
                          'd MMMM yyyy',
                          'id_ID',
                        ).format(_selectedDate),
                        style: GoogleFonts.lato(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: AppColors.bgDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isEdit ? 'Simpan Perubahan' : 'Tambah Transaksi',
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
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              Icon(account.icon, color: account.color, size: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  account.name,
                  style: GoogleFonts.lato(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            fmt.format(account.balance),
            style: GoogleFonts.lato(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Transaction List ──────────────────────────────────────────────────────
class _TxList extends StatelessWidget {
  final List<TransactionModel> transactions;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final void Function(TransactionModel, int) onEdit;
  final void Function(TransactionModel) onDelete;

  const _TxList({
    required this.transactions,
    required this.fmt,
    required this.dateFmt,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak ada transaksi',
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final tx = transactions[i];
        // index di full list
        final fullIndex = AppState.instance.transactions.indexWhere(
          (t) => t.id == tx.id,
        );
        final sign = tx.isIncome ? '+' : '-';
        final amtColor = tx.isIncome ? AppColors.income : AppColors.expense;

        return Dismissible(
          key: Key(tx.id),
          direction: DismissDirection.endToStart,
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
          confirmDismiss: (_) async {
            onDelete(tx);
            return false; // hapus lewat state, bukan dismiss otomatis
          },
          child: GestureDetector(
            onLongPress: () => onEdit(tx, fullIndex),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tx.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(tx.icon, color: tx.color, size: 20),
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
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tx.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tx.category,
                                style: GoogleFonts.lato(
                                  color: tx.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dateFmt.format(tx.date),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$sign${fmt.format(tx.amount)}',
                        style: GoogleFonts.lato(
                          color: amtColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Tombol edit
                      GestureDetector(
                        onTap: () => onEdit(tx, fullIndex),
                        child: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textMuted,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
