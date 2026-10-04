import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sos_provider.dart';

/// Dialog konfirmasi (dipakai pemicu goyang HP).
Future<void> showSosConfirm(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('HP terdeteksi digoyang'),
      content: const Text('Kirim SOS dan bagikan lokasi Anda?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Kirim SOS'),
        ),
      ],
    ),
  );
  if (ok == true) ref.read(sosProvider.notifier).trigger();
}
