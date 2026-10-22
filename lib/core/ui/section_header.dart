import 'package:flutter/material.dart';

/// Judul seksi dengan aksi opsional di sisi kanan.
///
/// Dipakai di awal tiap blok pada halaman beranda, ringkasan profil, dan
/// pengaturan agar pengguna cepat memindai struktur layar.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  /// Judul seksi; dipotong satu baris dengan ellipsis bila terlalu panjang.
  final String title;

  /// Label tombol aksi di kanan; tombol tidak dirender bila null.
  final String? actionLabel;

  /// Callback saat tombol aksi ditekan.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}
