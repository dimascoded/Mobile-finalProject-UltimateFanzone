import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/football_providers.dart';
import 'club_crest.dart';

class TeamPickerScreen extends ConsumerWidget {
  const TeamPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(favoriteKeyProvider);
    final crests = ref.watch(clubCrestProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Tim Favorit')),
      body: clubs.when(
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            return ListTile(
              leading: ClubCrest(
                crestUrl: crests[c.tla.toUpperCase()],
                tla: c.tla,
                color: c.colorValue,
                size: 40,
              ),
              title: Text(c.name),
              subtitle: Text('${c.stadium} • ${c.city}'),
              trailing:
                  c.key == selected ? const Icon(Icons.check_circle) : null,
              onTap: () async {
                await ref.read(favoriteKeyProvider.notifier).set(c.key);
                if (context.mounted) Navigator.pop(context);
              },
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat data klub: $e')),
      ),
    );
  }
}
