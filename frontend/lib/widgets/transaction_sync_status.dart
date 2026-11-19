import 'package:flutter/material.dart';

import '../core/app_state.dart';

class TransactionSyncStatus extends StatelessWidget {
  const TransactionSyncStatus({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final pending =
          state.pendingMutations > 0 || state.transactionsHasPendingWrites;
      final error = state.transactionsError;
      if (!pending && !state.transactionsFromCache && error == null) {
        return const SizedBox.shrink();
      }
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.secondaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(
                  pending ? Icons.sync : Icons.cloud_off,
                  size: 20,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error ??
                        (pending
                            ? 'Menyimpan transaksi, menunggu konfirmasi server...'
                            : 'Data cache/offline. Data terbaru dari server belum terkonfirmasi.'),
                    style: TextStyle(
                      color: colors.onSecondaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (error != null)
                  TextButton(
                    onPressed: state.retryTransactions,
                    child: const Text('Coba lagi'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
