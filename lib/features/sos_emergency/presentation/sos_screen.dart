import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../providers/sos_provider.dart';
import 'sos_hold_button.dart';

// STRUKTUR UI — SosScreen
// Ukuran: Scaffold > Center > SingleChildScrollView >
//         ConstrainedBox(maxWidth 720) > Column.
// [1] Tombol SOS      — SosHoldButton berukuran 200px untuk tekan-tahan
// [2] Petunjuk        — teks "Tahan 3 detik..." dan "atau goyangkan HP 2x"
// [3] Penafian        — catatan bahwa aplikasi tidak mengirim pesan dan
//                       koordinat hanya ditampilkan di perangkat
// [4] Status lokasi   — hasil pembacaan lokasi: teks, CircularProgressIndicator
//                        saat memuat, atau pesan galat
// [5] AppCard darurat — nomor darurat UK 999/112 (polisi, ambulans, umum)
// Tabel/kolom: tanpa tabel; satu kolom isi dengan kartu info.
// Sumber data: sosProvider.
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sosProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Darurat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SosHoldButton(
                size: 200,
                onTriggered: () => ref.read(sosProvider.notifier).trigger(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Tahan 3 detik untuk membaca lokasi Anda',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                'atau goyangkan HP 2x',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Aplikasi ini tidak mengirim pesan. Koordinat hanya ditampilkan '
                'di perangkat ini. Telepon 999/112 untuk layanan darurat.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              state.when(
                data: (m) => Text(
                  m ?? 'Tekan tombol untuk membaca lokasi Anda',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text(
                  'Gagal membaca lokasi: ${e.toString().replaceFirst('Exception: ', '')}',
                  textAlign: TextAlign.center,
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Column(children: [
                  Text(
                    'Nomor darurat UK (999/112)',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.error),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Polisi: 999 / 112', style: theme.textTheme.bodyMedium),
                  Text('Ambulans: 999 / 112',
                      style: theme.textTheme.bodyMedium),
                  Text('Umum: 999 / 112', style: theme.textTheme.bodyMedium),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
