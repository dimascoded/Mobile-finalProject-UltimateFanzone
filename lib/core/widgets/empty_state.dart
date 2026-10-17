import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;

  /// Tombol aksi opsional, dipakai saat kosong karena galat (bukan kosong
  /// beneran) supaya pengguna bisa langsung mencoba lagi.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline)),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ]),
      ),
    );
  }
}
