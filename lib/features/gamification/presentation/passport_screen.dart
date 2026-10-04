import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../football/providers/football_providers.dart';
import '../providers/gamification_providers.dart';

class PassportScreen extends ConsumerWidget {
  const PassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    final stamps = ref.watch(stampsProvider);
    final valid = ref.watch(chainValidProvider);
    final chain = ref.watch(chainProvider);

    if (club == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paspor Digital')),
        body: const Center(child: Text('Pilih tim favorit dulu')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Paspor Digital')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: Icon(valid ? Icons.verified : Icons.error,
                color: valid ? Colors.green : Colors.red),
            title: const Text('Validitas rantai'),
            subtitle: Text('${chain.length} blok'),
          ),
        ),
        Text('Stamp stadion ${club.name}', style: Theme.of(context).textTheme.titleMedium),
        for (final b in stamps)
          ListTile(
            leading: const Icon(Icons.approval, color: Colors.teal),
            title: Text('${b.data['landmark']}'),
            subtitle: Text('Blok #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}'),
          ),
      ]),
    );
  }
}