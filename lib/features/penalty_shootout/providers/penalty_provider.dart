import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/database/hive_service.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/penalty_rules.dart';

enum Phase { idle, ready, charging, resolved, finished }

/// Jendela deteksi puncak ayunan setelah tombol "Siap" ditekan (P2).
const swingWindow = Duration(milliseconds: 1500);

/// Jeda sebelum tendangan otomatis ditebak, supaya puncak ayunan sempat
/// tercatat.
const peakSettleDelay = Duration(milliseconds: 350);

/// Throttle status sensor agar layar tidak dibangun ulang 50x/detik (P3).
const sensorThrottle = Duration(milliseconds: 66);

/// Kunci Hive untuk menyimpan hari terakhir blok achievement dicetak (P3).
const _mintDayKey = 'penalty_block_day';

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

  /// Kemiringan HP (rad), positif = condong ke kanan. Diturunkan dari roll
  /// accelerometer (`atan2(x, z)`), bukan laju putar gyroscope.
  final double tiltZ;

  /// Puncak ayunan (m/s^2 di atas gravitasi) pada jendela aktif.
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
  bool get isFinished =>
      phase == Phase.finished || taken >= penaltyRules.attempts;
  bool get isSwinging => phase == Phase.charging;
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
        if (mounted) state = state.copyWith(demo: true);
      },
      cancelOnError: true,
    );

    // P1/P3: jangan sandera mode demo pada nilai tilt. Cukup tunggu event
    // accelerometer pertama; bila tidak pernah datang, sensor memang absen.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted && !_sensorSeen) state = state.copyWith(demo: true);
    });
  }

  final Ref _ref;
  final _rnd = Random();
  StreamSubscription<AccelerometerEvent>? _accelSub;

  /// True setelah event accelerometer pertama diterima.
  bool _sensorSeen = false;

  /// Puncak ayunan pada jendela aktif (tanpa peluruhan, P2).
  double _peak = 0;

  Timer? _peakTimer;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void _onAccel(AccelerometerEvent e) {
    _sensorSeen = true;
    if (!mounted) return;

    // Roll: sudut kemiringan kiri-kanan. HP datar -> 0, miring kanan -> positif.
    final roll = rollFromAccel(e.x, e.z);

    // Magnitudo ayunan: komponen yang berubah cepat, gravitasi (~9.8) dieliminasi.
    final m = shakeFromAccel(e.x, e.y, e.z);
    if (state.isSwinging && m > _peak) _peak = m;

    // P3: batasi emisi state ~15 Hz.
    final now = DateTime.now();
    if (now.difference(_lastEmit) < sensorThrottle) return;
    _lastEmit = now;
    state = state.copyWith(tiltZ: roll, shake: _peak, demo: false);

    // P2: deteksi puncak di dalam jendela ayunan, lalu tendang otomatis.
    if (state.isSwinging && m > penaltyRules.minShake && _peakTimer == null) {
      _peakTimer = Timer(peakSettleDelay, () {
        _peakTimer = null;
        if (!mounted || !state.isSwinging) return;
        shoot(manual: false);
      });
    }
  }

  /// Mulai sesi baru.
  void reset() {
    _cancelTimers();
    _peak = 0;
    state = const PenaltyState(phase: Phase.ready);
  }

  /// Siapkan tendangan: buka jendela ayunan dan tunggu puncak (P2).
  void arm() {
    if (state.isFinished) return;
    _cancelTimers();
    _peak = 0;
    state = state.copyWith(
      phase: Phase.charging,
      shake: 0,
      clearLast: true,
    );
  }

  /// Batalkan ayunan dan kembali ke posisi siap.
  void cancelSwing() {
    if (!state.isSwinging) return;
    _cancelTimers();
    _peak = 0;
    state = state.copyWith(phase: Phase.ready, shake: 0, clearLast: true);
  }

  /// Tendangkan bola. [manual] dipanggil dari tombol cadangan; ayunan otomatis
  /// memakai puncak yang sudah terdeteksi.
  Future<void> shoot({bool manual = true}) async {
    if (state.isFinished) return;
    // Tendangan manual tidak boleh menabrak ayunan yang sedang berjalan.
    if (state.isSwinging && manual) return;
    _cancelTimers();

    final double tiltZ;
    final double shake;
    if (state.demo) {
      final d = demoShot(_rnd);
      tiltZ = d.tiltZ;
      shake = d.shake;
    } else if (manual && _peak <= penaltyRules.minShake) {
      // Tombol cadangan tanpa ayunan: pakai kekuatan minimum yang sah.
      tiltZ = state.tiltZ;
      shake = penaltyRules.minShake + 0.5;
    } else {
      tiltZ = state.tiltZ;
      shake = _peak;
    }
    _peak = 0;

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

  void _cancelTimers() {
    _peakTimer?.cancel();
    _peakTimer = null;
  }

  Future<void> _mintAchievement() async {
    // P3: tidak ada blok achievement dari sesi tanpa gol, dan maksimal satu
    // blok per hari agar rantai tidak tumbuh karena main berulang.
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
      attempts: penaltyRules.attempts,
    );
    // Ambil dependensi sebelum await.
    final walletFuture = _ref.read(walletAddressProvider.future);
    final chain = _ref.read(chainProvider.notifier);
    final owner = await walletFuture;
    await chain.mint('achievement', {
      'game': 'Penalty Shootout',
      'score': score,
      'goals': goals,
      'attempts': penaltyRules.attempts,
      'hash': hash,
    }, owner);
    await HiveService.cache.put(_mintDayKey, today);
    if (mounted) state = state.copyWith(minted: true);
  }

  @override
  void dispose() {
    _cancelTimers();
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
    bool clearLast = false,
    int? score,
    bool? demo,
    bool? minted,
  }) =>
      PenaltyState(
        phase: phase ?? this.phase,
        results: results ?? this.results,
        tiltZ: tiltZ ?? this.tiltZ,
        shake: shake ?? this.shake,
        // P3: `last` harus bisa dikosongkan; `??` biasa tidak bisa.
        last: clearLast ? null : (last ?? this.last),
        score: score ?? this.score,
        demo: demo ?? this.demo,
        minted: minted ?? this.minted,
      );
}
