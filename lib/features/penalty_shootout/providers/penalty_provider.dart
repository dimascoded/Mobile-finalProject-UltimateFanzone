import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/database/hive_service.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/penalty_rules.dart';

enum Phase { aiming, swinging, resolved, finished }

const peakSettleDelay = Duration(milliseconds: 350);
const sensorThrottle = Duration(milliseconds: 66);
const kickCooldown = Duration(milliseconds: 600);
const aimHistoryWindow = Duration(milliseconds: 500);
const aimLatchOffset = Duration(milliseconds: 200);
const _sensorWatchdogDelay = Duration(seconds: 1);
const _mintDayKey = 'penalty_block_day';
const _maximumFlickSpeed = 1.0;
const _maximumFlickShake = 20.0;

class PenaltyState {
  const PenaltyState({
    this.phase = Phase.aiming,
    this.zone = KickZone.bottomMid,
    this.shake = 0,
    this.results = const [],
    this.last,
    this.score = 0,
    this.demo = false,
    this.minted = false,
    this.suddenDeath = false,
  });

  final Phase phase;
  final KickZone zone;
  final double shake;
  final List<KickResult> results;
  final KickResult? last;
  final int score;
  final bool demo;
  final bool minted;
  final bool suddenDeath;

  int get goals =>
      results.where((result) => result.outcome == ShotOutcome.goal).length;
  int get taken => results.length;
  int get remaining => max(0, PenaltyRules.attempts - taken);
  bool get isFinished => phase == Phase.finished;
  bool get isSwinging => phase == Phase.swinging;

  PenaltyState copyWith({
    Phase? phase,
    KickZone? zone,
    double? shake,
    List<KickResult>? results,
    KickResult? last,
    bool clearLast = false,
    int? score,
    bool? demo,
    bool? minted,
    bool? suddenDeath,
  }) =>
      PenaltyState(
        phase: phase ?? this.phase,
        zone: zone ?? this.zone,
        shake: shake ?? this.shake,
        results: results ?? this.results,
        last: clearLast ? null : (last ?? this.last),
        score: score ?? this.score,
        demo: demo ?? this.demo,
        minted: minted ?? this.minted,
        suddenDeath: suddenDeath ?? this.suddenDeath,
      );
}

final penaltyProvider =
    StateNotifierProvider.autoDispose<PenaltyNotifier, PenaltyState>(
  (ref) => PenaltyNotifier(ref),
);

class PenaltyNotifier extends StateNotifier<PenaltyState> {
  PenaltyNotifier(
    this._ref, {
    Stream<AccelerometerEvent> Function()? accelerometer,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        super(const PenaltyState()) {
    _aimingEnteredAt = _clock();
    _accelSub = (accelerometer ??
            () => accelerometerEventStream(
                  samplingPeriod: const Duration(milliseconds: 20),
                ))()
        .listen(
      _onAccel,
      onError: (Object _) {
        if (!mounted) return;
        _sensorWatchdog?.cancel();
        state = state.copyWith(demo: true);
      },
      cancelOnError: true,
    );
    _sensorWatchdog = Timer(_sensorWatchdogDelay, () {
      if (mounted && !_sensorSeen) state = state.copyWith(demo: true);
    });
  }

  final Ref _ref;
  final DateTime Function() _clock;
  final Random _rnd = Random();
  StreamSubscription<AccelerometerEvent>? _accelSub;

  Timer? _sensorWatchdog;
  Timer? _peakTimer;

  bool _sensorSeen = false;
  bool _needsPitchBaseline = true;
  double? _pitchBaseline;
  double _peak = 0;
  KickZone? _latchedZone;
  DateTime _aimingEnteredAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<({DateTime timestamp, KickZone zone})> _aimHistory = [];
  DateTime _lastSensorEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void _onAccel(AccelerometerEvent event) {
    _sensorSeen = true;
    _sensorWatchdog?.cancel();
    if (!mounted) return;

    final roll = rollFromAccel(event.x, event.y, event.z);
    final pitch = pitchFromAccel(event.y, event.z);
    final shake = shakeFromAccel(event.x, event.y, event.z);
    var changed = false;
    var aimZone = state.zone;

    if (state.phase == Phase.aiming) {
      if (_needsPitchBaseline) {
        _pitchBaseline = pitch;
        _needsPitchBaseline = false;
      }
      aimZone = zoneFromAim(
        roll: roll,
        pitchDelta: pitch - (_pitchBaseline ?? pitch),
      );
      changed = aimZone != state.zone;
      if (changed) state = state.copyWith(zone: aimZone);
      _recordAim(_clock(), aimZone);
      if (shake > kickTriggerThreshold &&
          _clock().difference(_aimingEnteredAt) >= kickCooldown) {
        _beginSwing(zone: _latchedAim(_clock()), initialPeak: shake);
        changed = true;
      }
    } else if (state.phase == Phase.swinging) {
      if (shake > _peak) {
        _peak = shake;
        changed = true;
      }
    }

    final demoChanged = state.demo;
    final now = _clock();
    if (now.difference(_lastSensorEmit) < sensorThrottle) return;
    _lastSensorEmit = now;
    if (changed || demoChanged) {
      state = state.copyWith(
        shake: state.phase == Phase.swinging ? _peak : state.shake,
        demo: false,
      );
    }
  }

  void _recordAim(DateTime timestamp, KickZone zone) {
    _aimHistory.add((timestamp: timestamp, zone: zone));
    final cutoff = timestamp.subtract(aimHistoryWindow);
    _aimHistory.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
  }

  KickZone _latchedAim(DateTime triggerTime) {
    if (_aimHistory.isEmpty) return state.zone;
    final target = triggerTime.subtract(aimLatchOffset);
    final priorSamples = _aimHistory
        .where((sample) => !sample.timestamp.isAfter(target))
        .toList(growable: false);
    if (priorSamples.isNotEmpty) return priorSamples.last.zone;
    return _aimHistory.first.zone;
  }

  void _beginSwing({required KickZone zone, required double initialPeak}) {
    if (state.phase != Phase.aiming) return;
    _peakTimer?.cancel();
    _latchedZone = zone;
    _peak = initialPeak;
    state = state.copyWith(phase: Phase.swinging, zone: zone, shake: _peak);
    _peakTimer?.cancel();
    _peakTimer = Timer(peakSettleDelay, () {
      _peakTimer = null;
      if (!mounted || state.phase != Phase.swinging) return;
      unawaited(_kick(zone: _latchedZone ?? state.zone, peak: _peak));
    });
  }

  /// Select a zone when no accelerometer is available.
  void selectZone(KickZone zone) {
    if (!state.demo || state.phase != Phase.aiming) return;
    state = state.copyWith(zone: zone);
  }

  /// Gesture fallback; `speed` is normalized from 0 (slow) to 1 (fast).
  Future<void> flick({
    required double dx,
    required double dy,
    required double speed,
  }) async {
    if (state.phase != Phase.aiming) return;
    _cancelSwingTimers();
    final zone = zoneFromAim(roll: dx, pitchDelta: dy);
    final shake = speed.clamp(0.0, _maximumFlickSpeed) * _maximumFlickShake;
    _latchedZone = zone;
    _peak = shake;
    state = state.copyWith(
      phase: Phase.swinging,
      zone: zone,
      shake: shake,
    );
    await _kick(zone: zone, peak: shake);
  }

  /// Kick the selected zone with demo power when sensors are unavailable.
  void demoKick() {
    if (!state.demo || state.phase != Phase.aiming) return;
    final shot = demoShot(_rnd);
    _latchedZone = state.zone;
    _peak = shot.shake;
    state = state.copyWith(phase: Phase.swinging, shake: _peak);
    _peakTimer?.cancel();
    _peakTimer = Timer(peakSettleDelay, () {
      _peakTimer = null;
      if (!mounted || state.phase != Phase.swinging) return;
      unawaited(_kick(zone: _latchedZone!, peak: _peak));
    });
  }

  /// Continue to the next attempt. The last result is cleared only here.
  void next() {
    if (state.phase != Phase.resolved) return;
    _cancelSwingTimers();
    _enterAiming();
    _peak = 0;
    state = state.copyWith(
      phase: Phase.aiming,
      clearLast: true,
      shake: 0,
    );
  }

  /// Start a fresh session. `last` remains visible until `next()` clears it.
  void reset() {
    _cancelAllTimers();
    _enterAiming();
    _peak = 0;
    state = PenaltyState(
      phase: Phase.aiming,
      zone: KickZone.bottomMid,
      last: state.last,
      demo: !_sensorSeen,
    );
  }

  Future<void> _kick({required KickZone zone, required double peak}) async {
    if (state.phase == Phase.finished) return;
    _cancelSwingTimers();
    final band = bandFromShake(peak);
    final keeperZone = chooseKeeperZone(
      _rnd,
      state.results.map((result) => result.zone).toList(),
    );
    final result = resolveKick(
      zone: zone,
      band: band,
      keeperZone: keeperZone,
    );
    final results = List<KickResult>.unmodifiable([...state.results, result]);
    final suddenDeath = inSuddenDeath(results, PenaltyRules.attempts);
    final finished = results.length >= PenaltyRules.attempts && !suddenDeath;
    state = state.copyWith(
      phase: finished ? Phase.finished : Phase.resolved,
      zone: zone,
      results: results,
      last: result,
      shake: peak,
      score: sessionScore(results),
      suddenDeath: suddenDeath,
    );
    if (finished) await _mintAchievement();
  }

  void _cancelSwingTimers() {
    _peakTimer?.cancel();
    _peakTimer = null;
  }

  void _cancelAllTimers() {
    _cancelSwingTimers();
    _sensorWatchdog?.cancel();
    _sensorWatchdog = null;
  }

  void _enterAiming() {
    _needsPitchBaseline = true;
    _pitchBaseline = null;
    _latchedZone = null;
    _aimingEnteredAt = _clock();
    _aimHistory.clear();
  }

  Future<void> _mintAchievement() async {
    if (state.minted || state.goals <= 0) return;
    final today = _clock().toIso8601String().substring(0, 10);
    if (HiveService.cache.get(_mintDayKey) == today) {
      if (mounted) state = state.copyWith(minted: true);
      return;
    }

    final goals = state.goals;
    final score = state.score;
    final hash = sessionHash(
      score: score,
      goals: goals,
      attempts: PenaltyRules.attempts,
    );
    final walletFuture = _ref.read(walletAddressProvider.future);
    final chain = _ref.read(chainProvider.notifier);
    final owner = await walletFuture;
    await chain.mint(
      'achievement',
      {
        'game': 'Penalty Shootout',
        'score': score,
        'goals': goals,
        'attempts': PenaltyRules.attempts,
        'hash': hash,
      },
      owner,
    );
    await _ref
        .read(cardMinterProvider)
        .mintCard(source: 'penalty', ref: 'penalty:$today');
    await HiveService.cache.put(_mintDayKey, today);
    if (mounted) state = state.copyWith(minted: true);
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _accelSub?.cancel();
    super.dispose();
  }
}
