import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/database/hive_service.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/penalty_rules.dart';

enum Phase { aiming, locked, swinging, resolved, finished }

const swingWindow = Duration(milliseconds: 1500);
const peakSettleDelay = Duration(milliseconds: 350);
const sensorThrottle = Duration(milliseconds: 66);
const aimLockDelay = Duration(milliseconds: 500);
const _sensorWatchdogDelay = Duration(seconds: 1);
const _swingTickInterval = Duration(milliseconds: 50);
const _mintDayKey = 'penalty_block_day';
const _maximumFlickSpeed = 1.0;
const _maximumFlickShake = 20.0;

class PenaltyState {
  const PenaltyState({
    this.phase = Phase.aiming,
    this.zone = KickZone.bottomMid,
    this.lockedZone,
    this.shake = 0,
    this.results = const [],
    this.last,
    this.score = 0,
    this.demo = false,
    this.minted = false,
    this.suddenDeath = false,
    this.swingSecondsLeft = 0,
  });

  final Phase phase;
  final KickZone zone;
  final KickZone? lockedZone;
  final double shake;
  final List<KickResult> results;
  final KickResult? last;
  final int score;
  final bool demo;
  final bool minted;
  final bool suddenDeath;
  final double swingSecondsLeft;

  int get goals =>
      results.where((result) => result.outcome == ShotOutcome.goal).length;
  int get taken => results.length;
  int get remaining => max(0, PenaltyRules.attempts - taken);
  bool get isFinished => phase == Phase.finished;
  bool get isSwinging => phase == Phase.swinging;

  PenaltyState copyWith({
    Phase? phase,
    KickZone? zone,
    KickZone? lockedZone,
    bool clearLockedZone = false,
    double? shake,
    List<KickResult>? results,
    KickResult? last,
    bool clearLast = false,
    int? score,
    bool? demo,
    bool? minted,
    bool? suddenDeath,
    double? swingSecondsLeft,
  }) =>
      PenaltyState(
        phase: phase ?? this.phase,
        zone: zone ?? this.zone,
        lockedZone: clearLockedZone ? null : (lockedZone ?? this.lockedZone),
        shake: shake ?? this.shake,
        results: results ?? this.results,
        last: clearLast ? null : (last ?? this.last),
        score: score ?? this.score,
        demo: demo ?? this.demo,
        minted: minted ?? this.minted,
        suddenDeath: suddenDeath ?? this.suddenDeath,
        swingSecondsLeft: swingSecondsLeft ?? this.swingSecondsLeft,
      );
}

final penaltyProvider =
    StateNotifierProvider.autoDispose<PenaltyNotifier, PenaltyState>(
  (ref) => PenaltyNotifier(ref),
);

class PenaltyNotifier extends StateNotifier<PenaltyState> {
  PenaltyNotifier(this._ref) : super(const PenaltyState()) {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(
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
  final Random _rnd = Random();
  StreamSubscription<AccelerometerEvent>? _accelSub;

  Timer? _sensorWatchdog;
  Timer? _aimLockTimer;
  Timer? _peakTimer;
  Timer? _swingTimer;

  bool _sensorSeen = false;
  bool _needsPitchBaseline = true;
  bool _swingTriggered = false;
  double? _pitchBaseline;
  double _peak = 0;
  KickZone? _candidateZone;
  KickZone? _demoKickZone;
  DateTime? _swingStartedAt;
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
      changed = _trackAimZone(aimZone);
    } else if (state.phase == Phase.swinging) {
      if (shake > _peak) {
        _peak = shake;
        changed = true;
      }
      if (shake > 4 && !_swingTriggered) {
        _swingTriggered = true;
        _schedulePeakKick();
      }
    }

    final demoChanged = state.demo;
    final now = DateTime.now();
    if (now.difference(_lastSensorEmit) < sensorThrottle) return;
    _lastSensorEmit = now;
    if (changed || demoChanged) {
      state = state.copyWith(
        zone: aimZone,
        shake: state.phase == Phase.swinging ? _peak : state.shake,
        demo: false,
      );
    }
  }

  bool _trackAimZone(KickZone zone) {
    if (_candidateZone == zone) return false;
    _candidateZone = zone;
    _aimLockTimer?.cancel();
    _aimLockTimer = Timer(aimLockDelay, () {
      if (!mounted || state.phase != Phase.aiming || _candidateZone != zone) {
        return;
      }
      _lock(zone);
    });
    return true;
  }

  void _lock(KickZone zone) {
    if (state.phase != Phase.aiming) return;
    _aimLockTimer?.cancel();
    _aimLockTimer = null;
    state = state.copyWith(
      phase: Phase.locked,
      zone: zone,
      lockedZone: zone,
      shake: 0,
      swingSecondsLeft: 0,
    );
  }

  /// Lock the current crosshair zone when the player taps the screen.
  void lockNow() {
    if (state.phase != Phase.aiming) return;
    _lock(_candidateZone ?? state.zone);
  }

  /// Start the swing-detection window from a locked zone.
  void startSwing() {
    if (state.phase != Phase.locked || state.lockedZone == null) return;
    _cancelSwingTimers();
    _peak = 0;
    _swingTriggered = false;
    _demoKickZone = null;
    _swingStartedAt = DateTime.now();

    if (state.demo) {
      final shot = demoShot(_rnd);
      _demoKickZone = zoneFromAim(
        roll: shot.roll,
        pitchDelta: shot.pitchDelta,
      );
      _peak = shot.shake;
      _swingTriggered = true;
      state = state.copyWith(
        phase: Phase.swinging,
        zone: _demoKickZone!,
        lockedZone: _demoKickZone,
        shake: _peak,
        swingSecondsLeft: swingWindow.inMilliseconds / 1000,
      );
      _schedulePeakKick();
    } else {
      state = state.copyWith(
        phase: Phase.swinging,
        shake: 0,
        swingSecondsLeft: swingWindow.inMilliseconds / 1000,
      );
    }

    _swingTimer = Timer.periodic(_swingTickInterval, (_) => _tickSwing());
  }

  void _tickSwing() {
    if (!mounted || state.phase != Phase.swinging) {
      _swingTimer?.cancel();
      _swingTimer = null;
      return;
    }
    final elapsed =
        DateTime.now().difference(_swingStartedAt ?? DateTime.now());
    final left = swingWindow - elapsed;
    if (left <= Duration.zero) {
      if (!_swingTriggered) {
        cancelSwing();
        return;
      }
      _swingTimer?.cancel();
      _swingTimer = null;
      state = state.copyWith(swingSecondsLeft: 0, shake: _peak);
      return;
    }
    state = state.copyWith(
      swingSecondsLeft: left.inMilliseconds / 1000,
      shake: _peak,
    );
  }

  void _schedulePeakKick() {
    _peakTimer?.cancel();
    _peakTimer = Timer(peakSettleDelay, () {
      _peakTimer = null;
      if (!mounted || state.phase != Phase.swinging) return;
      final zone = _demoKickZone ?? state.lockedZone ?? state.zone;
      unawaited(_kick(zone: zone, peak: _peak));
    });
  }

  void _returnToAiming() {
    _cancelSwingTimers();
    _aimLockTimer?.cancel();
    _aimLockTimer = null;
    _needsPitchBaseline = true;
    _pitchBaseline = null;
    _candidateZone = null;
    _peak = 0;
    _swingTriggered = false;
    _swingStartedAt = null;
    state = state.copyWith(
      phase: Phase.aiming,
      clearLockedZone: true,
      shake: 0,
      swingSecondsLeft: 0,
    );
  }

  /// Cancel the active swing and return to aiming without changing the session.
  void cancelSwing() {
    if (state.phase != Phase.swinging) return;
    _returnToAiming();
  }

  /// Gesture fallback; `speed` is normalized from 0 (slow) to 1 (fast).
  Future<void> flick({
    required double dx,
    required double dy,
    required double speed,
  }) async {
    if (state.phase != Phase.aiming && state.phase != Phase.locked) return;
    _cancelSwingTimers();
    final zone = zoneFromAim(roll: dx, pitchDelta: dy);
    final shake = speed.clamp(0.0, _maximumFlickSpeed) * _maximumFlickShake;
    state = state.copyWith(
      phase: Phase.swinging,
      zone: zone,
      lockedZone: zone,
      shake: shake,
    );
    await _kick(zone: zone, peak: shake);
  }

  /// Continue to the next attempt. The last result is cleared only here.
  void next() {
    if (state.phase != Phase.resolved) return;
    _cancelSwingTimers();
    _needsPitchBaseline = true;
    _pitchBaseline = null;
    _candidateZone = null;
    _peak = 0;
    _swingTriggered = false;
    _demoKickZone = null;
    state = state.copyWith(
      phase: Phase.aiming,
      clearLockedZone: true,
      clearLast: true,
      shake: 0,
      swingSecondsLeft: 0,
    );
  }

  /// Start a fresh session. `last` remains visible until `next()` clears it.
  void reset() {
    _cancelAllTimers();
    _needsPitchBaseline = true;
    _pitchBaseline = null;
    _candidateZone = null;
    _peak = 0;
    _swingTriggered = false;
    _demoKickZone = null;
    _swingStartedAt = null;
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
      lockedZone: zone,
      results: results,
      last: result,
      shake: peak,
      score: sessionScore(results),
      suddenDeath: suddenDeath,
      swingSecondsLeft: 0,
    );
    if (finished) await _mintAchievement();
  }

  void _cancelSwingTimers() {
    _peakTimer?.cancel();
    _peakTimer = null;
    _swingTimer?.cancel();
    _swingTimer = null;
    _swingStartedAt = null;
  }

  void _cancelAllTimers() {
    _cancelSwingTimers();
    _aimLockTimer?.cancel();
    _aimLockTimer = null;
    _sensorWatchdog?.cancel();
    _sensorWatchdog = null;
  }

  Future<void> _mintAchievement() async {
    if (state.minted || state.goals <= 0) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
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
