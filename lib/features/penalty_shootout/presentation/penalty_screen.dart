import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/permission_gate.dart';
import '../data/penalty_rules.dart';
import '../providers/penalty_provider.dart';

class PenaltyScreen extends ConsumerStatefulWidget {
  const PenaltyScreen({super.key});

  @override
  ConsumerState<PenaltyScreen> createState() => _PenaltyScreenState();
}

class _PenaltyScreenState extends ConsumerState<PenaltyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _execution;
  bool _animationComplete = false;

  @override
  void initState() {
    super.initState();
    _execution = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener(_onAnimationStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(penaltyProvider.notifier).reset();
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _animationComplete = true);
    }
  }

  void _onStateChanged(PenaltyState? previous, PenaltyState next) {
    final oldCount = previous?.results.length ?? 0;
    if (next.results.length <= oldCount) return;

    unawaited(HapticFeedback.lightImpact());
    switch (next.last?.outcome) {
      case ShotOutcome.goal:
        unawaited(HapticFeedback.heavyImpact());
      case ShotOutcome.saved:
      case ShotOutcome.overBar:
        unawaited(HapticFeedback.mediumImpact());
      case null:
        break;
    }

    if (!mounted) return;
    setState(() => _animationComplete = false);
    _execution.forward(from: 0);
  }

  @override
  void dispose() {
    _execution
      ..removeStatusListener(_onAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PenaltyState>(penaltyProvider, _onStateChanged);
    final state = ref.watch(penaltyProvider);
    final notifier = ref.read(penaltyProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Penalty Shootout')),
      body: PermissionGate(
        permissionKey: 'sensors',
        icon: Icons.vibration,
        title: 'Butuh sensor HP',
        message:
            'Accelerometer membaca arah dan kekuatan ayunan. Jika sensor tidak tersedia, tendangan demo dan geser cepat tetap bisa digunakan.',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Scoreboard(state: state),
            const SizedBox(height: 12),
            if (state.results.isNotEmpty) ...[
              _ResultChips(results: state.results),
              const SizedBox(height: 12),
            ],
            _PhaseInstruction(state: state),
            const SizedBox(height: 12),
            Stack(
              children: [
                AnimatedBuilder(
                  animation: _execution,
                  builder: (context, _) => _GoalBoard(
                    state: state,
                    progress: Curves.easeInOutCubic.transform(_execution.value),
                    onTap:
                        state.phase == Phase.aiming ? notifier.lockNow : null,
                    onPanEnd: (details) => _handlePanEnd(details, notifier),
                  ),
                ),
                if (state.phase == Phase.resolved &&
                    _animationComplete &&
                    state.last != null)
                  Positioned.fill(
                    child: _ResultOverlay(
                      result: state.last!,
                      onNext: notifier.next,
                    ),
                  ),
              ],
            ),
            if (state.phase == Phase.swinging) ...[
              const SizedBox(height: 16),
              _PowerMeter(shake: state.shake),
            ],
            if (state.demo) ...[
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
              const SizedBox(height: 8),
              Text(
                'Atau geser cepat di gawang',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (state.results.isNotEmpty) ...[
              const SizedBox(height: 16),
              _KickHistory(results: state.results),
            ],
            const SizedBox(height: 16),
            _PhaseControls(state: state, notifier: notifier),
          ],
        ),
      ),
    );
  }

  void _handlePanEnd(DragEndDetails details, PenaltyNotifier notifier) {
    final velocity = details.velocity.pixelsPerSecond;
    final magnitude = velocity.distance;
    if (magnitude < 100) return;
    unawaited(
      notifier.flick(
        dx: (velocity.dx / magnitude).clamp(-1.0, 1.0),
        dy: (-velocity.dy / magnitude).clamp(-1.0, 1.0),
        speed: (magnitude / 1000).clamp(0.0, 1.0),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state});

  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _ScoreValue(
            label: 'GOL / TENDANGAN',
            value: '${state.goals} / ${state.taken}',
          ),
        ),
        Expanded(
          child: _ScoreValue(label: 'SKOR', value: '${state.score}'),
        ),
        if (state.suddenDeath)
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                'Sudden death',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScoreValue extends StatelessWidget {
  const _ScoreValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ResultChips extends StatelessWidget {
  const _ResultChips({required this.results});

  final List<KickResult> results;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var index = 0; index < results.length; index++)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              _outcomeIcon(results[index].outcome),
              size: 17,
              color: _outcomeColor(context, results[index].outcome),
            ),
            label:
                Text('${index + 1}. ${_outcomeLabel(results[index].outcome)}'),
          ),
      ],
    );
  }
}

class _PhaseInstruction extends StatelessWidget {
  const _PhaseInstruction({required this.state});

  final PenaltyState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state.phase) {
      Phase.aiming =>
        'Miringkan HP untuk membidik, tahan 0,5 detik untuk mengunci',
      Phase.locked => 'Arah terkunci. Tekan Ayun lalu ayunkan HP',
      Phase.swinging =>
        'Ayun ${state.swingSecondsLeft.toStringAsFixed(1)} dtk • puncak ${state.shake.toStringAsFixed(1)}',
      Phase.resolved => 'Hasil tendangan',
      Phase.finished => 'Sesi selesai',
    };
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      textAlign: TextAlign.center,
    );
  }
}

class _GoalBoard extends StatelessWidget {
  const _GoalBoard({
    required this.state,
    required this.progress,
    required this.onTap,
    required this.onPanEnd,
  });

  final PenaltyState state;
  final double progress;
  final VoidCallback? onTap;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final selectedZone = switch (state.phase) {
      Phase.aiming => state.zone,
      Phase.locked || Phase.swinging => state.lockedZone ?? state.zone,
      Phase.resolved || Phase.finished => state.last?.zone ?? state.zone,
    };
    final isLocked =
        state.phase == Phase.locked || state.phase == Phase.swinging;
    final executing =
        (state.phase == Phase.resolved || state.phase == Phase.finished) &&
            state.last != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanEnd: onPanEnd,
      child: AspectRatio(
        aspectRatio: 1.55,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final ball = _ballPosition(size, executing);
            final keeper = _keeperPosition(size, executing);
            final ballOrigin = Offset(size.width / 2, size.height * 0.96);
            final keeperOrigin = Offset(size.width / 2, size.height * 0.76);

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            for (final zone in const [
                              KickZone.topLeft,
                              KickZone.topMid,
                              KickZone.topRight,
                            ])
                              Expanded(
                                child: _ZoneCell(
                                  zone: zone,
                                  selected: selectedZone == zone,
                                  locked: isLocked && selectedZone == zone,
                                  outcome: executing && state.last?.zone == zone
                                      ? state.last?.outcome
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            for (final zone in const [
                              KickZone.bottomLeft,
                              KickZone.bottomMid,
                              KickZone.bottomRight,
                            ])
                              Expanded(
                                child: _ZoneCell(
                                  zone: zone,
                                  selected: selectedZone == zone,
                                  locked: isLocked && selectedZone == zone,
                                  outcome: executing && state.last?.zone == zone
                                      ? state.last?.outcome
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (executing) ...[
                    Positioned(
                      left: keeper.dx - 18,
                      top: keeper.dy - 18,
                      child: const _KeeperMarker(),
                    ),
                    Positioned(
                      left: ball.dx - 14,
                      top: ball.dy - 14,
                      child: const _BallMarker(),
                    ),
                  ] else ...[
                    Positioned(
                      left: keeperOrigin.dx - 18,
                      top: keeperOrigin.dy - 18,
                      child: const _KeeperMarker(),
                    ),
                    Positioned(
                      left: ballOrigin.dx - 14,
                      top: ballOrigin.dy - 14,
                      child: const _BallMarker(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Offset _ballPosition(Size size, bool executing) {
    if (!executing || state.last == null) {
      return Offset(size.width / 2, size.height * 0.96);
    }
    final target = _zoneCenter(size, state.last!.zone);
    final end = state.last!.outcome == ShotOutcome.overBar
        ? Offset(target.dx, -18)
        : target;
    return Offset.lerp(
        Offset(size.width / 2, size.height * 0.96), end, progress)!;
  }

  Offset _keeperPosition(Size size, bool executing) {
    final start = Offset(size.width / 2, size.height * 0.76);
    if (!executing || state.last == null) return start;
    return Offset.lerp(
        start, _zoneCenter(size, state.last!.keeperZone), progress)!;
  }

  static Offset _zoneCenter(Size size, KickZone zone) {
    final x = switch (zone.col) {
      0 => size.width / 6,
      1 => size.width / 2,
      _ => size.width * 5 / 6,
    };
    final y = zone.row == 0 ? size.height / 4 : size.height * 3 / 4;
    return Offset(x, y);
  }
}

class _ZoneCell extends StatelessWidget {
  const _ZoneCell({
    required this.zone,
    required this.selected,
    required this.locked,
    required this.outcome,
  });

  final KickZone zone;
  final bool selected;
  final bool locked;
  final ShotOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? locked
            ? scheme.primary
            : scheme.secondaryContainer
        : scheme.surface;
    final foreground = selected && locked
        ? scheme.onPrimary
        : selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;
    final borderColor = selected
        ? locked
            ? scheme.onPrimary
            : scheme.primary
        : scheme.outlineVariant;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: selected ? 2.5 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (locked)
                  Icon(Icons.lock, size: 17, color: foreground)
                else if (outcome != null)
                  Icon(_outcomeIcon(outcome!), size: 17, color: foreground),
                const SizedBox(height: 3),
                Text(
                  _zoneLabel(zone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BallMarker extends StatelessWidget {
  const _BallMarker();

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black87, width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: const Icon(Icons.sports_soccer, size: 20, color: Colors.black87),
      );
}

class _KeeperMarker extends StatelessWidget {
  const _KeeperMarker();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.tertiary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.onTertiary, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(Icons.shield, size: 21, color: scheme.onTertiary),
    );
  }
}

class _PowerMeter extends StatelessWidget {
  const _PowerMeter({required this.shake});

  final double shake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Puncak ayunan ${shake.toStringAsFixed(1)}',
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: 18,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: (shake / 20).clamp(0.0, 1.0),
                    minHeight: 12,
                    color: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                for (final threshold in [4.0, 8.0, 16.0])
                  Positioned(
                    left: constraints.maxWidth * threshold / 20 - 1,
                    child: Container(
                      width: 2,
                      height: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Lemah <4', style: theme.textTheme.labelSmall),
            Text('Sweet 8–16', style: theme.textTheme.labelSmall),
            Text('Terlalu keras >16', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({required this.result, required this.onNext});

  final KickResult result;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.scrim.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _outcomeTitle(result.outcome),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                result.reason,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Tendangan berikutnya'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KickHistory extends StatelessWidget {
  const _KickHistory({required this.results});

  final List<KickResult> results;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Riwayat tendangan',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (var index = 0; index < results.length; index++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              child: Text('${index + 1}',
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            title: Text(_outcomeLabel(results[index].outcome)),
            subtitle: Text(
              '${_zoneLabel(results[index].zone)} • ${results[index].reason}',
            ),
            trailing: Text(_bandLabel(results[index].band)),
          ),
      ],
    );
  }
}

class _PhaseControls extends StatelessWidget {
  const _PhaseControls({required this.state, required this.notifier});

  final PenaltyState state;
  final PenaltyNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.phase == Phase.finished) {
      return Column(
        children: [
          Text(
            '${state.goals}/${PenaltyRules.attempts} gol, skor ${state.score}',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (state.minted)
            const Text('Pencapaian tersimpan permanen di Paspormu')
          else if (state.goals > 0)
            const Text('Pencapaian hari ini sudah tersimpan'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: notifier.reset,
            icon: const Icon(Icons.replay),
            label: const Text('Main lagi'),
          ),
        ],
      );
    }

    if (state.phase == Phase.locked) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: notifier.startSwing,
          icon: const Icon(Icons.sports_soccer),
          label: const Text('Ayun'),
        ),
      );
    }

    if (state.phase == Phase.swinging) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: notifier.cancelSwing,
          icon: const Icon(Icons.close),
          label: const Text('Batal'),
        ),
      );
    }

    if (state.phase == Phase.aiming) {
      return Text(
        'Bidik salah satu zona gawang atau geser cepat untuk menendang.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return const SizedBox.shrink();
  }
}

String _zoneLabel(KickZone zone) => switch (zone) {
      KickZone.topLeft => 'Kiri atas',
      KickZone.topMid => 'Tengah atas',
      KickZone.topRight => 'Kanan atas',
      KickZone.bottomLeft => 'Kiri bawah',
      KickZone.bottomMid => 'Tengah bawah',
      KickZone.bottomRight => 'Kanan bawah',
    };

String _outcomeLabel(ShotOutcome outcome) => switch (outcome) {
      ShotOutcome.goal => 'Gol',
      ShotOutcome.saved => 'Ditepis',
      ShotOutcome.overBar => 'Melambung',
    };

String _outcomeTitle(ShotOutcome outcome) => switch (outcome) {
      ShotOutcome.goal => 'GOL!',
      ShotOutcome.saved => 'DITEPIS!',
      ShotOutcome.overBar => 'MELAMBUNG!',
    };

IconData _outcomeIcon(ShotOutcome outcome) => switch (outcome) {
      ShotOutcome.goal => Icons.sports_soccer,
      ShotOutcome.saved => Icons.back_hand_outlined,
      ShotOutcome.overBar => Icons.north_east,
    };

Color _outcomeColor(BuildContext context, ShotOutcome outcome) {
  final scheme = Theme.of(context).colorScheme;
  return switch (outcome) {
    ShotOutcome.goal => scheme.primary,
    ShotOutcome.saved => scheme.tertiary,
    ShotOutcome.overBar => scheme.error,
  };
}

String _bandLabel(PowerBand band) => switch (band) {
      PowerBand.none => 'Tanpa ayun',
      PowerBand.weak => 'Lemah',
      PowerBand.sweet => 'Sweet spot',
      PowerBand.tooHard => 'Terlalu keras',
    };
