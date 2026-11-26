import 'package:flutter/material.dart';

import '../core/app_state.dart';

class TransactionSyncStatus extends StatelessWidget {
  const TransactionSyncStatus({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final pending = state.pendingMutations > 0;
      final error = state.transactionsError;
      final failure = state.transactionWriteFailure;
      if (!state.hasTransactionNotice) {
        return const SizedBox.shrink();
      }
      final message = pending
          ? 'Permintaan sedang berjalan, menunggu konfirmasi server. Koneksi diperlukan untuk menyimpan.'
          : (failure != null && error != null
                    ? '${failure.message}\n$error'
                    : failure?.message ?? error) ??
                (state.transactionsHasPendingWrites
                    ? 'Data lokal belum dikonfirmasi server. Ini bukan konfirmasi bahwa transaksi tersimpan.'
                    : state.transactionsFromCache
                    ? 'Data dari cache. Bisa dibaca; menyimpan, mengubah, dan menghapus memerlukan koneksi server.'
                    : 'Memuat data, menunggu konfirmasi server...');
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.secondaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      pending ? Icons.sync : Icons.cloud_off,
                      size: 20,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: colors.onSecondaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!pending && (error != null || failure != null))
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: state.retryTransactions,
                        child: Text(error != null ? 'Coba lagi' : 'Muat data'),
                      ),
                      if (failure != null)
                        TextButton(
                          onPressed: state.dismissTransactionWriteFailure,
                          child: const Text('Tutup pesan'),
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
