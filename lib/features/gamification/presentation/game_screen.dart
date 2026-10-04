import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/gamification_providers.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(gameProvider);
    final notifier = ref.read(gameProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Speed Tapper')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            Text('Skor: ${g.score}/${GameState.winScore}',
                style: Theme.of(context).textTheme.titleLarge),
            Text('⏱ ${g.secondsLeft}s', style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
        Expanded(
          child: Stack(children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              alignment: Alignment(g.dx, g.dy),
              child: GestureDetector(
                onTap: notifier.tap,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.flight, color: Colors.white, size: 36),
                ),
              ),
            ),
            if (!g.running)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (g.finished)
                    Text(
                      g.won
                          ? '🏆 Menang! Blok achievement dicetak ke rantai Paspor (cek tab Profil)'
                          : 'Waktu habis. Capai ${GameState.winScore} poin untuk menang.',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: notifier.start,
                    child: Text(g.finished ? 'Main Lagi' : 'Mulai'),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
