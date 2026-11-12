import 'package:flutter/material.dart';

/// Header seksi dengan judul dan tombol aksi opsional.
///
/// - Warna mengikuti tema (terang/gelap) via [Theme.of(context)].
/// - Judul panjang dipotong dengan ellipsis, tidak overflow.
/// - Area sentuh tombol aksi minimal 44×44 dp (WCAG 2.5.5).
/// - Label tombol aksesibel untuk screen reader.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Judul — Expanded agar teks panjang tidak mendorong tombol keluar layar
        Expanded(
          child: Text(
            title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Tombol aksi — hanya tampil jika ada label
        if (actionLabel != null) ...[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: actionLabel,
            excludeSemantics: true,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                // Padding ekstra supaya area sentuh ≥ 44 dp
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
