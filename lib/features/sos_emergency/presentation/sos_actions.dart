import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sos_provider.dart';

/// Dialog konfirmasi (dipakai pemicu goyang HP).
Future<void> showSosConfirm(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('HP terdeteksi digoyang'),
      content: const Text(
          'Baca lokasi Anda sekarang? Catatan: lokasi hanya ditampilkan di '
          'perangkat ini, tidak dikirim ke siapa pun.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Baca lokasi'),
        ),
      ],
    ),
  );
  if (ok == true) ref.read(sosProvider.notifier).trigger();
}
