import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/pill_badge.dart';
import '../../../core/ui/scrim_image.dart';
import '../../../core/widgets/permission_gate.dart';
import '../data/penalty_rules.dart';
import '../providers/penalty_provider.dart';

// STRUKTUR UI — PenaltyScreen
// Ukuran: Scaffold + AppBar, body dibungkus PermissionGate, lalu Center +
// ConstrainedBox(maxWidth: 720) + ListView satu kolom
// [1] _Scoreboard — kartu skor AppCard: gol/tendangan, skor, badge sudden death
// [2] _ResultChips — Wrap badge hasil tiap tendangan bernomor
// [3] _PhaseInstruction — teks instruksi per fase (aiming/swinging/resolved/finished)
// [4] _GoalBoard — papan gawang AspectRatio 1.55: 2 baris x 3 _ZoneCell, _BallMarker/_KeeperMarker, gesture geser
// [5] _ResultOverlay — overlay hasil tendangan di atas papan: judul, alasan, tombol lanjut
// [6] _PowerMeter — meter kekuatan ayunan (segmen Lemah/Pas/Terlalu keras) + label band
// [7] _KickHistory — daftar riwayat tendangan satu kolom (ListTile: zona, alasan, band)
// [8] _PhaseControls — tombol aksi per fase: tendang demo, main lagi, atau pesan geser
// Tabel/kolom: tanpa tabel; papan gawang 2 baris x 3 kolom zona, sisanya daftar kartu satu kolom
// Sumber data: penaltyProvider

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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                        progress:
                            Curves.easeInOutCubic.transform(_execution.value),
                        onZoneTap: state.demo && state.phase == Phase.aiming
                            ? notifier.selectZone
                            : null,
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
                if (state.phase == Phase.swinging ||
                    ((state.phase == Phase.resolved ||
                            state.phase == Phase.finished) &&
                        state.last != null)) ...[
                  const SizedBox(height: 16),
                  _PowerMeter(
                    shake: state.shake,
                    band:
                        state.phase == Phase.swinging ? null : state.last?.band,
                  ),
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
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
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
            const PillBadge(label: 'Sudden death', tone: PillTone.accent),
        ],
      ),
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
          PillBadge(
            label: '${index + 1}. ${_outcomeLabel(results[index].outcome)}',
            icon: Icon(
              _outcomeIcon(results[index].outcome),
              size: 17,
              color: _outcomeColor(context, results[index].outcome),
            ),
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
      Phase.aiming => 'Miringkan HP untuk membidik, lalu ayunkan untuk '
          'menendang. Makin kencang ayunannya, makin kuat tendangannya.',
      Phase.swinging => 'Mengukur kekuatan ayunan...',
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
    required this.onZoneTap,
    required this.onPanEnd,
  });

  final PenaltyState state;
  final double progress;
  final ValueChanged<KickZone>? onZoneTap;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final selectedZone = switch (state.phase) {
      Phase.aiming => state.zone,
      Phase.swinging => state.zone,
      Phase.resolved || Phase.finished => state.last?.zone ?? state.zone,
    };
    final executing =
        (state.phase == Phase.resolved || state.phase == Phase.finished) &&
            state.last != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
                borderRadius: BorderRadius.circular(8),
              ),
              foregroundDecoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ScrimImage(
                      assetPath: AppImages.gameGoal,
                      borderRadius: 8,
                      scrim: 0.35,
                      fallbackColors: [
                        Color.lerp(
                          Colors.black,
                          Theme.of(context).colorScheme.primary,
                          0.35,
                        )!,
                        Colors.black,
                      ],
                    ),
                  ),
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
                                  onTap: onZoneTap == null
                                      ? null
                                      : () => onZoneTap!(zone),
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
                                  onTap: onZoneTap == null
                                      ? null
                                      : () => onZoneTap!(zone),
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
    required this.onTap,
    required this.outcome,
  });

  final KickZone zone;
  final bool selected;
  final VoidCallback? onTap;
  final ShotOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fz = context.fz;

    final Color background;
    final Color borderColor;
    final double borderWidth;
    if (selected) {
      background = scheme.primary.withValues(alpha: 0.30);
      borderColor = fz.accent;
      borderWidth = 3;
    } else if (outcome != null) {
      background = scheme.primary.withValues(alpha: 0.45);
      borderColor = Colors.white.withValues(alpha: 0.6);
      borderWidth = 2;
    } else {
      background = Colors.black.withValues(alpha: 0.18);
      borderColor = Colors.white.withValues(alpha: 0.35);
      borderWidth = 1;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (outcome != null)
                Icon(_outcomeIcon(outcome!), size: 17, color: Colors.white),
              if (outcome != null) const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _zoneLabel(zone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 3),
                    ],
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
  const _PowerMeter({required this.shake, this.band});

  final double shake;
  final PowerBand? band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 4,
          children: [
            Text('Puncak ayunan ${shake.toStringAsFixed(1)} m/s²',
                style: theme.textTheme.labelLarge),
            if (band != null)
              Text(_bandLabel(band!), style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            const scale = tooHardPowerThreshold + sweetPowerThreshold;
            return SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          flex: sweetPowerThreshold.toInt(),
                          child: _meterSegment(
                            theme.colorScheme.tertiary,
                            isFirst: true,
                          ),
                        ),
                        Expanded(
                          flex: (tooHardPowerThreshold - sweetPowerThreshold)
                              .toInt(),
                          child: _meterSegment(theme.colorScheme.primary),
                        ),
                        Expanded(
                          flex: sweetPowerThreshold.toInt(),
                          child: _meterSegment(
                            theme.colorScheme.error,
                            isLast: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final threshold in [
                    weakPowerThreshold,
                    sweetPowerThreshold,
                    tooHardPowerThreshold,
                  ])
                    Positioned(
                      left: constraints.maxWidth * threshold / scale - 1,
                      child: Container(
                        width: 2,
                        height: 18,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  Positioned(
                    left: (constraints.maxWidth * shake / scale - 2)
                        .clamp(0.0, constraints.maxWidth - 4),
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.black87),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Lemah', style: theme.textTheme.labelSmall),
            Text('Pas', style: theme.textTheme.labelSmall),
            Text('Terlalu keras', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }

  Widget _meterSegment(Color color,
          {bool isFirst = false, bool isLast = false}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.75),
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(8) : Radius.zero,
            right: isLast ? const Radius.circular(8) : Radius.zero,
          ),
        ),
      );
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
        child: SingleChildScrollView(
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

    if (state.phase == Phase.aiming) {
      if (state.demo) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: notifier.demoKick,
            icon: const Icon(Icons.sports_soccer),
            label: const Text('Tendang'),
          ),
        );
      }
      return Text(
        'Geser cepat di gawang untuk tendangan alternatif.',
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
