import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/mock_data.dart';

/// Kartu rekening/akun yang mengikuti tema terang maupun gelap.
///
/// Warna teks dan latar diambil dari [Theme.of(context).colorScheme] agar
/// otomatis benar di kedua tema tanpa hardcode.
class AccountCard extends StatelessWidget {
  final AccountModel account;

  const AccountCard({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp\u00A0',
      decimalDigits: 0,
    );
    final formattedBalance = fmt.format(account.balance);

    return Semantics(
      label: '${account.name}, ${account.subtitle}, saldo $formattedBalance',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // ── Ikon rekening ───────────────────────────────────────────
            _AccountIcon(icon: account.icon, color: account.color),
            const SizedBox(width: 12),

            // ── Nama dan subtitle — Expanded mencegah overflow ──────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.name,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.subtitle,
                    style: tt.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Saldo — intrinsic width, tidak overflow ────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _BalanceText(value: formattedBalance),
                const SizedBox(height: 2),
                Text('Saldo', style: tt.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widget private ────────────────────────────────────────────────────

class _AccountIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _AccountIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Teks saldo yang menyusut secara otomatis jika terlalu lebar.
/// Nominal besar (misal Rp 999.999.999) tetap terbaca di layar 320 dp.
class _BalanceText extends StatelessWidget {
  final String value;

  const _BalanceText({required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      // Batasi lebar sisi kanan agar tidak menekan nama di sisi kiri.
      // Pada lebar 320 dp dengan padding 14+14+ikon 44+gap 12+gap 8 = 92 dp,
      // sisa layar ~228 dp. Kolom kanan mendapat maks 148 dp.
      constraints: const BoxConstraints(maxWidth: 148),
      child: Text(
        value,
        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      ),
    );
  }
}
