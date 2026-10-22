import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_card.dart';

/// Kartu statistik ringkas berisi satu angka utama.
///
/// Menampilkan nilai besar, label, dan keterangan singkat di dalam [AppCard].
/// Dipakai untuk ringkasan profil dan blok statistik beranda. Nilai utama
/// diperkecil otomatis bila panjang agar tidak membungkus baris.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    this.icon,
    required this.value,
    required this.label,
    required this.detail,
    this.onTap,
  });

  /// Ikon kecil di atas nilai, opsional.
  final Widget? icon;

  /// Nilai utama yang ditonjolkan, mis. jumlah stempel.
  final String value;

  /// Label singkat yang menjelaskan nilai, mis. "Stempel".
  final String label;

  /// Keterangan tambahan di bawah label, mis. "3 dari 12 kartu".
  final String detail;

  /// Aksi saat kartu diketuk; bila null kartu tidak dapat diklik.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fz = theme.extension<FanzoneColors>();
    final semanticsLabel = '$label: $value, $detail';

    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: IconTheme(
                  data: IconThemeData(color: theme.colorScheme.primary),
                  child: icon!,
                ),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: theme.textTheme.bodySmall),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fz?.textMuted ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
