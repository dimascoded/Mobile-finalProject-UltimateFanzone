import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/time_utils.dart';
import '../../football/providers/football_providers.dart';
import '../providers/pundit_provider.dart';

class PunditScreen extends ConsumerWidget {
  const PunditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(punditProvider);
    final club = ref.watch(favoriteClubProvider);
    final loading = state.isLoading;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pundit AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (club != null) Text('Tim favorit: ${club.name}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading
                ? null
                : () => ref.read(punditProvider.notifier).generate(),
            icon: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(loading ? 'Menulis analisis…' : 'Buat Analisis Pundit'),
          ),
          const SizedBox(height: 12),
          state.when(
            data: (r) {
              if (r == null) {
                return const Text('Belum ada analisis. Tekan tombol di atas.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r.warning != null)
                    Card(
                      color: scheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 20, color: scheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Analisis terbaru gagal dimuat, jadi yang tampil '
                                'adalah hasil tersimpan. ${r.warning}',
                                style: TextStyle(
                                    color: scheme.onTertiaryContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (r.fromCache)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Chip(
                        avatar: const Icon(Icons.history, size: 18),
                        label: Text(r.cachedAt == null
                            ? 'Data tersimpan (tanpa waktu)'
                            : 'Data tersimpan • ${TimeUtils.formatHm(TimeUtils.wib(r.cachedAt!))} WIB'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Text(r.text, style: const TextStyle(height: 1.4)),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analisis gagal',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(e.toString().replaceFirst('Exception: ', '')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(punditProvider.notifier).generate(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
