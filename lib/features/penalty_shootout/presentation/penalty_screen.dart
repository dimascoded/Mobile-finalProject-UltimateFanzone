import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/permission_gate.dart';
import '../data/penalty_rules.dart';
import '../providers/penalty_provider.dart';

class PenaltyScreen extends ConsumerStatefulWidget {
  const PenaltyScreen({super.key});

  @override
  ConsumerState<PenaltyScreen> createState() => _PenaltyScreenState();
}

class _PenaltyScreenState extends ConsumerState<PenaltyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(penaltyProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(penaltyProvider);
    final n = ref.read(penaltyProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Penalty Shootout')),
      body: PermissionGate(
        permissionKey: 'sensors',
        icon: Icons.vibration,
        title: 'Butuh sensor HP',
        message:
            'Game ini memakai accelerometer: kemiringan HP menentukan arah '
            'dan ayunan menentukan kekuatan tendangan. Jalankan di HP fisik.',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Scoreboard(state: s),
            const SizedBox(height: 16),
            _Goal(state: s),
            const SizedBox(height: 16),
            _Meters(state: s),
            const SizedBox(height: 16),
            _Result(state: s),
            const SizedBox(height: 20),
            _Controls(state: s, notifier: n),
            if (s.demo) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Sensor tidak terdeteksi, memakai mode demo dengan tendangan acak.',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state});
  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Circle(label: 'GOL', value: '${state.goals}'),
        Text(
          'dari ${penaltyRules.attempts}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        _Circle(label: 'SKOR', value: '${state.score}'),
      ],
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(value, style: Theme.of(context).textTheme.titleLarge),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Gawang dengan penanda posisi bola berdasarkan kemiringan HP.
class _Goal extends StatelessWidget {
  const _Goal({required this.state});
  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final norm = (state.tiltZ / penaltyRules.aimTolerance).clamp(-1.5, 1.5);
    // -1.5..1.5 -> 0..1 posisi horizontal di dalam gawang
    final x = ((norm + 1.5) / 3.0).clamp(0.02, 0.98);

    return AspectRatio(
      aspectRatio: 2.2,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline, width: 3),
          borderRadius: BorderRadius.circular(6),
          color: scheme.surfaceContainerHighest,
        ),
        child: Stack(
          children: [
            // Kiper di tengah bawah
            Align(
              alignment: const Alignment(0, 0.75),
              child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    shape: BoxShape.circle,
                  )),
            ),
            // Penanda arah tendangan
            Align(
              alignment: Alignment(-1 + 2 * x, -0.35),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: state.demo ? scheme.tertiary : scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            if (state.last != null)
              Align(
                alignment: const Alignment(0, 0.95),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _outcomeText(state.last!.outcome),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _outcomeText(ShotOutcome o) => switch (o) {
        ShotOutcome.goal => 'GOL!',
        ShotOutcome.savedByKeeper => 'Ditepis kiper',
        ShotOutcome.tooWeak => 'Terlalu lemah',
        ShotOutcome.wide => 'Melebar',
      };
}

class _Meters extends StatelessWidget {
  const _Meters({required this.state});
  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    final power = penaltyRules.power(state.shake);
    final tiltNorm =
        (state.tiltZ.abs() / penaltyRules.aimTolerance).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Arah (roll accelerometer): '
          '${degrees(state.tiltZ).toStringAsFixed(1)} derajat',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: tiltNorm, minHeight: 8),
        const SizedBox(height: 12),
        Text(
          'Kekuatan (puncak accelerometer): '
          '${state.shake.toStringAsFixed(1)} m/s2',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: power, minHeight: 8),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state});
  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    if (state.results.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < state.results.length; i++)
          Chip(
            avatar: Icon(
              state.results[i].isGoal ? Icons.sports_soccer : Icons.block,
              size: 18,
              color: state.results[i].isGoal ? Colors.green : Colors.red,
            ),
            label: Text('${i + 1}'),
          ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.notifier});
  final PenaltyState state;
  final PenaltyNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isFinished) {
      return Column(
        children: [
          Text(
            'Sesi selesai: ${state.goals}/${penaltyRules.attempts} gol, skor ${state.score}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.minted)
            const Text('Blok achievement sudah dicetak ke rantai Paspor.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: notifier.reset,
            icon: const Icon(Icons.replay),
            label: const Text('Main lagi'),
          ),
        ],
      );
    }

    final steady = steadyEnough(state.tiltZ);
    return Column(
      children: [
        if (!steady)
          const Text('Tahan HP datar dulu sebelum menendang.',
              style: TextStyle(color: Colors.orange)),
        const SizedBox(height: 8),
        if (state.isSwinging) ...[
          Text(
            'Ayunkan HP sekarang… puncak ${state.shake.toStringAsFixed(1)} m/s2',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
              'Tendangan menembak otomatis saat puncak ayunan terdeteksi.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: notifier.cancelSwing,
              icon: const Icon(Icons.close),
              label: const Text('Batal ayun'),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: notifier.arm,
              icon: const Icon(Icons.sports_soccer),
              label: Text(
                  'Siap & Ayun (${state.taken + 1}/${penaltyRules.attempts})'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => notifier.shoot(),
              icon: const Icon(Icons.flash_on),
              label: const Text('Tendang manual (tanpa ayun)'),
            ),
          ),
        ],
      ],
    );
  }
}
