import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../providers/football_providers.dart';
import 'club_crest.dart';

// STRUKTUR UI — TeamPickerScreen
// Ukuran: Scaffold > Center > ConstrainedBox(maxWidth 720) > ListView.builder.
// [1] Daftar klub   — satu AppCard per klub: ClubCrest, nama klub, serta
//                      stadium dan kota
// [2] Penanda pilih — border primary 2px dan ikon centang pada klub
//                      favorit yang sedang terpilih
// [3] Status muat   — CircularProgressIndicator saat memuat, teks galat saat
//                      data klub gagal dimuat
// Tabel/kolom: tanpa tabel; daftar kartu satu kolom.
// Sumber data: clubsProvider, favoriteKeyProvider, clubCrestProvider.
class TeamPickerScreen extends ConsumerWidget {
  const TeamPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(favoriteKeyProvider);
    final crests = ref.watch(clubCrestProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Tim Favorit')),
      body: clubs.when(
        data: (list) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                final isSelected = c.key == selected;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    foregroundDecoration: isSelected
                        ? BoxDecoration(
                            border: Border.all(color: scheme.primary, width: 2),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          )
                        : null,
                    child: AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      onTap: () async {
                        final saved = await ref
                            .read(favoriteKeyProvider.notifier)
                            .set(c.key);
                        if (!context.mounted) return;
                        if (!saved) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Tim favorit disimpan di perangkat, tetapi belum tersimpan ke akun. Akan dicoba lagi saat masuk.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(context);
                      },
                      child: Row(
                        children: [
                          ClubCrest(
                            crestUrl: crests[c.tla.toUpperCase()],
                            tla: c.tla,
                            color: c.colorValue,
                            size: 40,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: theme.textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${c.stadium} • ${c.city}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Icon(Icons.check_circle, color: scheme.primary),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat data klub: $e')),
      ),
    );
  }
}
