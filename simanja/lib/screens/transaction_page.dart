import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../core/mock_data.dart';
import '../widgets/section_header.dart';

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
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<TransactionModel> get _allTx => MockData.transactions;
  List<TransactionModel> get _incomeTx =>
      MockData.transactions.where((t) => t.isIncome).toList();
  List<TransactionModel> get _expenseTx =>
      MockData.transactions.where((t) => !t.isIncome).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Transaksi & Akun'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: () {})],
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
          // ── Account Cards ─────────────────────────────────────────────
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
              separatorBuilder: (_, s) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) =>
                  _AccountMiniCard(account: MockData.accounts[i], fmt: _fmt),
            ),
          ),

          const SizedBox(height: 4),

          // ── Divider ───────────────────────────────────────────────────
          const Divider(
            color: AppColors.divider,
            height: 24,
            indent: 16,
            endIndent: 16,
          ),

          // ── Transactions ──────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _TxList(transactions: _allTx, fmt: _fmt, dateFmt: _dateFmt),
                _TxList(transactions: _incomeTx, fmt: _fmt, dateFmt: _dateFmt),
                _TxList(transactions: _expenseTx, fmt: _fmt, dateFmt: _dateFmt),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
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

class _TxList extends StatelessWidget {
  final List<TransactionModel> transactions;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _TxList({
    required this.transactions,
    required this.fmt,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(
        child: Text(
          'Tidak ada transaksi',
          style: GoogleFonts.lato(color: AppColors.textMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: transactions.length,
      separatorBuilder: (_, s) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final tx = transactions[i];
        final sign = tx.isIncome ? '+' : '-';
        final amtColor = tx.isIncome ? AppColors.income : AppColors.expense;
        return Container(
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
                  Text(
                    tx.id,
                    style: GoogleFonts.lato(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
