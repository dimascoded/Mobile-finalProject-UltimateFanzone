import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/football_providers.dart';

class TeamPickerScreen extends ConsumerWidget {
  const TeamPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);
    final selected = ref.watch(favoriteKeyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Tim Favorit')),
      body: clubs.when(
        data: (list) => ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final c = list[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: c.colorValue,
                child: Text(
                  c.tla,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: ThemeData.estimateBrightnessForColor(c.colorValue) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ),
              title: Text(c.name),
              subtitle: Text('${c.stadium} • ${c.city}'),
              trailing: c.key == selected ? const Icon(Icons.check_circle) : null,
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
