import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../gamification/providers/gamification_providers.dart';
import '../data/penalty_rules.dart';

enum Phase { idle, ready, charging, resolved, finished }

class PenaltyState {
  const PenaltyState({
    this.phase = Phase.idle,
    this.results = const [],
    this.tiltZ = 0,
    this.shake = 0,
    this.last,
    this.score = 0,
    this.demo = false,
    this.minted = false,
  });

  final Phase phase;
  final List<ShotResult> results;

  /// Kemiringan HP (rad), positif = condong ke kanan.
  final double tiltZ;

  /// Magnitudo ayunan (m/s^2).
  final double shake;
  final ShotResult? last;
  final int score;

  /// Sensor tidak tersedia, memakai tendangan acak.
  final bool demo;

  /// Blok achievement sudah dicetak.
  final bool minted;

  int get goals => results.where((r) => r.isGoal).length;
  int get taken => results.length;
  int get remaining => penaltyRules.attempts - taken;
  bool get isFinished => phase == Phase.finished || taken >= penaltyRules.attempts;
}

final penaltyProvider =
    StateNotifierProvider.autoDispose<PenaltyNotifier, PenaltyState>(
  (ref) => PenaltyNotifier(ref),
);

class PenaltyNotifier extends StateNotifier<PenaltyState> {
  PenaltyNotifier(this._ref) : super(const PenaltyState()) {
    _gyroSub = gyroscopeEventStream().listen(
      (e) {
        if (!mounted) return;
        state = state.copyWith(tiltZ: e.z, demo: false);
      },
      onError: (Object _) {
        if (mounted) state = state.copyWith(demo: true);
      },
      cancelOnError: true,
    );
    // Magnitudo ayunan: akar jumlah kuadrat komponen accelerometer, dikurangi gravitasi.
    _accelSub = accelerometerEventStream().listen((e) {
      if (!mounted) return;
      final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      _peakShake = max(_peakShake * 0.90, m - 9.8);
      state = state.copyWith(shake: _peakShake);
    }, onError: (Object _) {}, cancelOnError: true);
  }

  final Ref _ref;
  final _rnd = Random();
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _peakShake = 0;

  bool _sensorsReady = false;

  void _ensureSensorsChecked() {
    if (_sensorsReady) return;
    _sensorsReady = true;
    // Beri 1 detik agar sensor terinisialisasi; kalau tidak ada event gyroscope,
    // gyroscope, aktifkan mode demo.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted && state.tiltZ == 0 && !state.demo) {
        state = state.copyWith(demo: true);
      }
    });
  }

  /// Mulai sesi baru.
  void reset() {
    _peakShake = 0;
    state = const PenaltyState(phase: Phase.ready);
  }

  /// Siapkan tendangan: reset ayunan, tunggu HP diam.
  void arm() {
    _peakShake = 0;
    state = state.copyWith(phase: Phase.ready, shake: 0, last: null);
  }

  /// Tendangkan bola. Memakai sensor, atau nilai acak bila mode demo.
  Future<void> shoot() async {
    _ensureSensorsChecked();
    if (state.isFinished) return;

    final double tiltZ;
    final double shake;
    if (state.demo) {
      final d = demoShot(_rnd);
      tiltZ = d.tiltZ;
      shake = d.shake;
    } else {
      tiltZ = state.tiltZ;
      shake = state.shake;
    }

    final result = penaltyRules.evaluate(
      tiltZ: tiltZ,
      shake: shake,
      keeperDive: keeperDive(_rnd),
    );
    final results = [...state.results, result];
    final finished = results.length >= penaltyRules.attempts;

    state = state.copyWith(
      phase: finished ? Phase.finished : Phase.resolved,
      results: results,
      last: result,
      shake: 0,
      score: sessionScore(results),
    );

    if (finished) await _mintAchievement();
  }

  Future<void> _mintAchievement() async {
    if (state.minted) return;
    final goals = state.goals;
    final hash = sessionHash(
      score: state.score,
      goals: goals,
      attempts: penaltyRules.attempts,
    );
    // Ambil dependensi sebelum await.
    final walletFuture = _ref.read(walletAddressProvider.future);
    final chain = _ref.read(chainProvider.notifier);
    final owner = await walletFuture;
    await chain.mint('achievement', {
      'game': 'Penalty Shootout',
      'score': state.score,
      'goals': goals,
      'attempts': penaltyRules.attempts,
      'hash': hash,
    }, owner);
    if (mounted) state = state.copyWith(minted: true);
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }
}

extension on PenaltyState {
  PenaltyState copyWith({
    Phase? phase,
    List<ShotResult>? results,
    double? tiltZ,
    double? shake,
    ShotResult? last,
    int? score,
    bool? demo,
    bool? minted,
  }) =>
      PenaltyState(
        phase: phase ?? this.phase,
        results: results ?? this.results,
        tiltZ: tiltZ ?? this.tiltZ,
        shake: shake ?? this.shake,
        last: last ?? this.last,
        score: score ?? this.score,
        demo: demo ?? this.demo,
        minted: minted ?? this.minted,
      );
}
