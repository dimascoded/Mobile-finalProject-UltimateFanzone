import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/empty_state.dart';
import '../../football/data/models.dart';
import '../../football/presentation/match_center_screen.dart';
import '../../football/providers/football_providers.dart';
import '../providers/lens_provider.dart';

class LensScreen extends ConsumerWidget {
  const LensScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    final state = ref.watch(lensProvider);

    if (club == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lens (OCR Harga)')),
        body: const EmptyState(
          icon: Icons.favorite_border,
          title: 'Pilih tim favorit dulu',
          message: 'Tim favorit dipakai untuk mengenali klub pada hasil OCR.',
        ),
      );
    }

    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lens (OCR Harga)'),
        actions: [
          if (state.hasValue && state.value != null)
            IconButton(
              tooltip: 'Hapus hasil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(lensProvider.notifier).clear(),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Ambil foto struk atau karcis',
                    child: ElevatedButton.icon(
                      onPressed: busy
                          ? null
                          : () =>
                              ref.read(lensProvider.notifier).scan(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Kamera'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Pilih foto dari galeri',
                    child: ElevatedButton.icon(
                      onPressed: busy
                          ? null
                          : () =>
                              ref.read(lensProvider.notifier).scan(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeri'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const LinearProgressIndicator(semanticsLabel: 'Memproses foto'),
          Expanded(
            child: state.when(
              skipLoadingOnRefresh: true,
              data: (r) => r == null
                  ? const EmptyState(
                      icon: Icons.document_scanner,
                      title: 'Belum ada hasil',
                      message:
                          'Ambil foto struk atau karcis. Teks akan dibaca otomatis '
                          'lalu tiap harga dikonversi ke Rupiah.',
                    )
                  : _ResultView(result: r),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Scan gagal',
                message: e.toString().replaceFirst('Exception: ', ''),
                action: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(lensProvider.notifier).scan(ImageSource.camera),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result});

  final LensResult result;

  /// Buka Match Center dengan pencarian sudah terisi nama klub, jadi pengguna
  /// langsung melihat jadwal klub yang terbaca di struk/karcis.
  ///
  /// `matchQueryProvider` adalah `autoDispose`: nilainya dibuang begitu tidak
  /// ada pendengar. Jadi penulisan dilakukan setelah halaman baru selesai dibangun,
  /// lewat `addPostFrameCallback` di dalam `builder`.
  void _openFixtures(BuildContext context, WidgetRef ref, PlClub club) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (routeContext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!routeContext.mounted) return;
          ProviderScope.containerOf(routeContext)
              .read(matchQueryProvider.notifier)
              .state = club.name;
        });
        return const MatchCenterScreen();
      },
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (result.imagePath.isNotEmpty)
          // UI8: pengecekan file dipindah ke dalam FutureBuilder, bukan
          // File(...).existsSync() yang jalan tiap frame saat build.
          _ImagePreview(path: result.imagePath),
        const SizedBox(height: 12),
        if (result.mentionedClubs.isNotEmpty) ...[
          Text('Klub terdeteksi', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in result.mentionedClubs)
                Chip(
                  avatar: CircleAvatar(
                    backgroundColor: c.colorValue,
                    child: Text(
                      c.tla,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  label: Text(c.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // UI7: dari hasil OCR langsung ke jadwal klub yang terbaca.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in result.mentionedClubs)
                OutlinedButton.icon(
                  onPressed: () => _openFixtures(context, ref, c),
                  icon: const Icon(Icons.event_note, size: 18),
                  label: Text('Lihat jadwal ${c.shortName}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ] else if (result.text.trim().isNotEmpty) ...[
          Text('Klub tidak terdeteksi pada teks OCR.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
        ],
        Text('Mata uang: ${result.currency}', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (result.prices.isEmpty)
          Text('Tidak ada nominal harga yang terbaca.', style: theme.textTheme.bodyMedium)
        else
          for (final p in result.prices)
            Semantics(
              label: p.idr == null
                  ? '${p.amount} ${result.currency}, konversi Rupiah tidak tersedia'
                  : '${p.amount} ${result.currency}, setara ${_rp(p.idr!)} Rupiah',
              excludeSemantics: true,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.line),
                subtitle: Text(
                  p.idr == null
                      ? '${p.amount} ${result.currency}'
                      : '${p.amount} ${result.currency} ˜ Rp ${_rp(p.idr!)}',
                ),
              ),
            ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Teks OCR mentah'),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                result.text.trim().isEmpty ? '(kosong)' : result.text,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ribuan tanpa paket intl (tidak ada di pubspec): 1234567.89 -> "1.234.568".
String _rp(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// UI8: `File(...).existsSync()` di dalam build() memblokir UI thread setiap
/// frame. Dipindah ke FutureBuilder supaya sekali saja saat widget dibangun.
class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late final Future<bool> _exists = File(widget.path).exists();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _exists,
      builder: (context, snap) {
        final ok = snap.data ?? false;
        if (!ok) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Foto tidak lagi tersedia di perangkat.',
                style: Theme.of(context).textTheme.bodySmall),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(widget.path),
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: 'Foto hasil pindai',
          ),
        );
      },
    );
  }
}
