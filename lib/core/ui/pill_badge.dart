import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Nada warna untuk [PillBadge].
///
/// Menentukan pasangan latar dan teks yang dipakai lencana, sehingga status
/// yang sama selalu tampil dengan warna yang sama di seluruh aplikasi.
enum PillTone {
  /// Netral: latar permukaan tinggi dengan teks utama.
  neutral,

  /// Aksen: warna kuning [FanzoneColors.accent] dengan teks gelap.
  accent,

  /// Sukses: warna primer tema dengan teks kontrasnya.
  success,
}

/// Lencana berbentuk kapsul untuk label status singkat.
///
/// Dipakai untuk menandai status seperti "Berlangsung", "Selesai", atau
/// jumlah item pada kartu fitur. Label dipangkas satu baris dengan ellipsis
/// supaya lencana tidak merusak layout saat terlalu panjang.
class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = PillTone.neutral,
  });

  /// Teks singkat pada lencana; idealnya satu sampai tiga kata.
  final String label;

  /// Ikon opsional di sebelah kiri label.
  final Widget? icon;

  /// Nada warna lencana, default [PillTone.neutral].
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fz = context.fz;
    Color bg;
    Color fg;
    switch (tone) {
      case PillTone.accent:
        bg = fz.accent;
        fg = fz.onAccent;
        break;
      case PillTone.success:
        bg = scheme.primary;
        fg = scheme.onPrimary;
        break;
      case PillTone.neutral:
        bg = scheme.surfaceContainerHigh;
        fg = scheme.onSurface;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
