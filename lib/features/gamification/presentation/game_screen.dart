import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/scrim_image.dart';
import '../../penalty_shootout/data/penalty_rules.dart';
import '../data/reflex_rules.dart';
import '../providers/gamification_providers.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ReflexState>(reflexProvider, (previous, next) {
      if (next.saves > (previous?.saves ?? 0)) {
        unawaited(HapticFeedback.lightImpact());
      }
      if (next.lives < (previous?.lives ?? reflexLives)) {
        unawaited(HapticFeedback.heavyImpact());
      }
    });

    final state = ref.watch(reflexProvider);
    final notifier = ref.read(reflexProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Refleks Kiper')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: _Scoreboard(state: state),
                ),
                const SizedBox(height: 12),
                _LivesRow(lives: state.lives),
                const SizedBox(height: 20),
                _GoalGrid(
                  state: state,
                  onZoneTap: notifier.tapZone,
                ),
                const SizedBox(height: 12),
                if (state.running) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Bola datang',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Text(
                        '${state.remainingMs} ms',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: state.ballProgress,
                      minHeight: 10,
                      color: state.ballProgress > 0.75
                          ? scheme.error
                          : scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Tepuk zona yang berisi bola sebelum waktunya habis.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else if (state.gameOver) ...[
                  AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text('Permainan selesai',
                            style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          'Skor ${state.score}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Best score ${state.bestScore}'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: notifier.start,
                          icon: const Icon(Icons.replay),
                          label: const Text('Main lagi'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text('Siap menjaga gawang?',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text('Best score ${state.bestScore}'),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: notifier.start,
                          icon: const Icon(Icons.sports_soccer),
                          label: const Text('Mulai'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state});

  final ReflexState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Metric(label: 'SKOR', value: '${state.score}')),
        Expanded(child: _Metric(label: 'KOMBO', value: '${state.combo}')),
        Expanded(child: _Metric(label: 'LEVEL', value: '${state.level}')),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _LivesRow extends StatelessWidget {
  const _LivesRow({required this.lives});

  final int lives;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < reflexLives; index++) ...[
          Icon(
            index < lives ? Icons.favorite : Icons.favorite_border,
            color: index < lives ? scheme.error : scheme.outline,
            size: 25,
          ),
          if (index < reflexLives - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({required this.state, required this.onZoneTap});

  final ReflexState state;
  final ValueChanged<KickZone> onZoneTap;

  static const _zones = [
    [KickZone.topLeft, KickZone.topMid, KickZone.topRight],
    [KickZone.bottomLeft, KickZone.bottomMid, KickZone.bottomRight],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1.35,
      child: Container(
        padding: const EdgeInsets.all(5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ScrimImage(
                assetPath: AppImages.gameGoal,
                borderRadius: 10,
                scrim: 0.35,
                fallbackColors: [
                  Color.lerp(Colors.black, scheme.primary, 0.35)!,
                  Colors.black,
                ],
              ),
            ),
            Column(
              children: [
                for (final row in _zones)
                  Expanded(
                    child: Row(
                      children: [
                        for (final zone in row)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: _ZoneCell(
                                zone: zone,
                                active: state.running && state.zone == zone,
                                progress: state.ballProgress,
                                onTap: state.running
                                    ? () => onZoneTap(zone)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneCell extends StatelessWidget {
  const _ZoneCell({
    required this.zone,
    required this.active,
    required this.progress,
    required this.onTap,
  });

  final KickZone zone;
  final bool active;
  final double progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = 0.58 + 0.62 * progress;
    final approach = -0.7 + 1.1 * progress;
    return Material(
      color: active
          ? scheme.surface.withValues(alpha: 0.9)
          : Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 45),
          decoration: BoxDecoration(
            border: Border.all(
              color:
                  active ? scheme.error : Colors.white.withValues(alpha: 0.35),
              width: active ? 3 : 1,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  _zoneName(zone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active ? scheme.onSurface : Colors.white,
                      ),
                ),
              ),
              if (active)
                Align(
                  alignment: Alignment(0, approach),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.error, width: 2),
                      ),
                      child: Icon(
                        Icons.sports_soccer,
                        color: scheme.onErrorContainer,
                        size: 25,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _zoneName(KickZone zone) => switch (zone) {
      KickZone.topLeft => 'Kiri atas',
      KickZone.topMid => 'Tengah atas',
      KickZone.topRight => 'Kanan atas',
      KickZone.bottomLeft => 'Kiri bawah',
      KickZone.bottomMid => 'Tengah bawah',
      KickZone.bottomRight => 'Kanan bawah',
    };
