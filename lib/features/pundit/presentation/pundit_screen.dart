import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../football/providers/football_providers.dart';
import '../providers/pundit_provider.dart';

class PunditScreen extends ConsumerWidget {
  const PunditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(punditProvider);
    final club = ref.watch(favoriteClubProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pundit AI')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (club != null) Text('Tim favorit: ${club.name}'),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => ref.read(punditProvider.notifier).generate(),
          child: const Text('Buat Analisis Pundit'),
        ),
        const SizedBox(height: 12),
        state.when(
          data: (r) => r == null ? const Text('Belum ada analisis') : Text(r.text),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
        ),
      ]),
    );
  }
}