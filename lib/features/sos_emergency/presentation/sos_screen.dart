import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sos_provider.dart';
import 'sos_hold_button.dart';

class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('SOS Darurat')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SosHoldButton(
              size: 200,
              onTriggered: () => ref.read(sosProvider.notifier).trigger(),
            ),
            const SizedBox(height: 12),
            const Text('Tahan 3 detik untuk mengirim SOS'),
            const Text('atau goyangkan HP 2x', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 24),
            state.when(
              data: (m) => Text(m ?? 'Lokasi Anda akan dibagikan sebagai peringatan darurat'),
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Gagal mengirim SOS: $e'),
            ),
            const SizedBox(height: 24),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('Nomor darurat UK (999/112)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const Text('Polisi: 999 / 112'),
                  const Text('Ambulans: 999 / 112'),
                  const Text('Umum: 999 / 112'),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}