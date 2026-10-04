import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/widgets/empty_state.dart';
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
        body: const Center(child: Text('Pilih tim favorit dulu')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lens (OCR Harga)')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => ref.read(lensProvider.notifier).scan(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Kamera'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => ref.read(lensProvider.notifier).scan(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeri'),
              ),
            ),
          ]),
        ),
        Expanded(
          child: state.when(
            data: (r) => r == null
                ? const EmptyState(icon: Icons.document_scanner, title: 'Belum ada hasil')
                : ListView(padding: const EdgeInsets.all(12), children: [
                    if (r.imagePath.isNotEmpty && File(r.imagePath).existsSync())
                      Image.file(File(r.imagePath), height: 240),
                    const SizedBox(height: 8),
                    Text('Mata uang: ${r.currency}'),
                    for (final p in r.prices)
                      ListTile(
                        title: Text(p.line),
                        subtitle: p.idr == null ? Text('${p.amount} ${r.currency}') : Text('${p.amount} ${r.currency} ˜ Rp ${p.idr!.toStringAsFixed(0)}'),
                      ),
                  ]),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
          ),
        ),
      ]),
    );
  }
}