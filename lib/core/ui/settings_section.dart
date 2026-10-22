import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_card.dart';

/// Grup baris pengaturan di dalam satu kartu.
///
/// Menyatukan beberapa [SettingsTile] di bawah satu judul seksi, dengan
/// pemisah tipis antar baris. Dipakai di halaman Profil untuk mengelompokkan
/// preferensi, data, dan aksi pengguna.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  /// Judul kelompok, ditampilkan dengan warna teks redup.
  final String title;

  /// Baris-baris isi seksi, biasanya [SettingsTile].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fz = theme.extension<FanzoneColors>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: fz?.textMuted ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Satu baris pengaturan bergaya daftar.
///
/// Menampilkan ikon, judul, keterangan opsional, dan kontrol di kanan (mis.
/// switch atau chevron). Baris destruktif seperti "Hapus akun" diberi warna
/// error agar tidak tertukar dengan aksi biasa.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  /// Ikon di sisi kiri baris.
  final Widget icon;

  /// Judul baris.
  final String title;

  /// Keterangan tambahan di bawah judul, dipotong maksimal tiga baris.
  final String? subtitle;

  /// Kontrol di sisi kanan baris, mis. switch, ikon, atau chevron.
  final Widget? trailing;

  /// Aksi saat baris diketuk; bila null baris tidak dapat diklik.
  final VoidCallback? onTap;

  /// Tandai baris sebagai aksi merusak (warna teks dan ikon memakai warna
  /// error tema).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: ListTile(
        leading: IconTheme(
          data: IconThemeData(
            color: destructive
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          child: icon,
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: destructive ? theme.colorScheme.error : null,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              )
            : null,
        trailing: trailing,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
    );
  }
}
