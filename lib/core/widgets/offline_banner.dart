import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/connectivity_provider.dart';

/// Spanduk peringatan mode offline.
///
/// Muncul otomatis di atas konten saat perangkat tidak punya koneksi, memberi
/// tahu pengguna bahwa data yang tampil berasal dari cache lokal. Status
/// koneksi diambil dari [onlineProvider] yang memeriksa koneksi berkala.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    if (online) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Mode offline - menampilkan data tersimpan',
              style: TextStyle(color: scheme.onErrorContainer)),
        ),
      ]),
    );
  }
}
