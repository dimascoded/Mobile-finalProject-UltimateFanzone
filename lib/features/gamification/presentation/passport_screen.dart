import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../providers/card_collection_provider.dart';
import '../providers/gamification_providers.dart';
import 'card_collection_screen.dart';

class PassportScreen extends ConsumerWidget {
  const PassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(stampProvider, (previous, next) {
      next.whenOrNull(
        data: (message) {
          if (message != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
        error: (error, _) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(error.toString().replaceFirst('Exception: ', ''))),
            );
          }
        },
      );
    });
    final club = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final stamps = ref.watch(stampsProvider);
    final valid = ref.watch(chainValidProvider);
    final demoMode = ref.watch(demoModeProvider);
    final busy = ref.watch(stampProvider).isLoading;
    final distance = ref.watch(stampDistanceProvider);
    final owned = ref.watch(ownedClubsProvider);

    if (club == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paspor Suporter')),
        body: const Center(child: Text('Pilih tim favorit dulu')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paspor Suporter')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  ClubCrest(
                    crestUrl: crests[club.tla.toUpperCase()],
                    tla: club.tla,
                    color: club.colorValue,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(club.name,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('${club.stadium} • ${club.city}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        demoMode
                            ? 'Mode demo aktif, GPS dilewati.'
                            : 'Cap tersedia dalam radius '
                                '${stampRadiusMeters.round()} m dari stadion.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (!demoMode)
                      IconButton(
                        tooltip: 'Perbarui jarak',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.invalidate(stampDistanceProvider),
                      ),
                  ],
                ),
                distance.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Mengukur jarak ke stadion…'),
                  ),
                  data: (m) => Text(
                    m == null
                        ? 'Jarak tidak diukur (GPS mati atau izin belum diberikan).'
                        : 'Anda $m m dari ${club.stadium}.'
                            '${m <= stampRadiusMeters.round() ? ' Dalam jangkauan!' : ' Terlalu jauh untuk cap GPS.'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  error: (e, _) => Text(
                    'Gagal mengukur jarak: ${e.toString().replaceFirst('Exception: ', '')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode demo'),
                  subtitle: const Text('Melewati pemeriksaan GPS'),
                  value: demoMode,
                  onChanged: (enabled) {
                    ref.read(demoModeProvider.notifier).state = enabled;
                    if (enabled) ref.invalidate(stampDistanceProvider);
                  },
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!demoMode) {
                            final allowed = await confirmPermission(
                              context,
                              ref,
                              permissionKey: 'location',
                              title: 'Izin lokasi untuk cap stadion',
                              message:
                                  'Lokasi digunakan untuk memeriksa jarak Anda dari stadion ${club.stadium}.',
                            );
                            if (!allowed || !context.mounted) return;
                          }
                          await ref.read(stampProvider.notifier).stamp(club);
                        },
                  icon: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.approval_outlined),
                  label: Text(busy ? 'Mencetak…' : 'Cap stamp'),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(valid ? Icons.verified : Icons.error,
                color: valid ? Colors.green : Colors.red),
            title: Text(valid ? 'Riwayat aman' : 'Riwayat tidak cocok'),
            subtitle: Text(valid
                ? 'Semua pencapaianmu tercatat dan belum pernah diubah.'
                : 'Ada catatan yang tidak sesuai. Coba cadangkan ulang.'),
          ),
        ),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.style_outlined),
            title: Text('Koleksi Kartu (${owned.length})'),
            subtitle: const Text('Lihat klub yang sudah kamu kumpulkan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardCollectionScreen(),
              ),
            ),
          ),
        ),
        Row(children: [
          ClubCrest(
            crestUrl: crests[club.tla.toUpperCase()],
            tla: club.tla,
            color: club.colorValue,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Stamp stadion ${club.name}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
        ]),
        for (final b in stamps)
          ListTile(
            leading: const Icon(Icons.approval, color: Colors.teal),
            title: Text('${b.data['stadium']}'),
            subtitle: Text(
                'Catatan #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}'),
          ),
      ]),
    );
  }
}
