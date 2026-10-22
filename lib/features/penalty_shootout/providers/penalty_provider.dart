import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/database/hive_service.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/penalty_rules.dart';

/// Tahap dalam satu sesi Penalty Shootout.
///
/// - [Phase.aiming]: pemain mengarahkan gol (arah/ayunan HP).
/// - [Phase.swinging]: ayunan terdeteksi, kekuatan dikumpulkan sampai peak.
/// - [Phase.resolved]: tendangan selesai, hasil tampil dan menunggu [PenaltyNotifier.next].
/// - [Phase.finished]: sesi selesai (termasuk kondisi sudden death).
enum Phase { aiming, swinging, resolved, finished }

/// Jeda sebelum kekuatan ayunan dikunci sebagai hasil tendangan (ms).
const peakSettleDelay = Duration(milliseconds: 350);

/// Throttle emisi state dari sensor akselerometer (ms).
const sensorThrottle = Duration(milliseconds: 66);

/// Jeda minimum antar dua ayunan agar tidak double-trigger (ms).
const kickCooldown = Duration(milliseconds: 600);

/// Jendela histori arah yang dipakai saat mengunci zona tendangan (ms).
const aimHistoryWindow = Duration(milliseconds: 500);

/// Offset ke belakang dari waktu trigger untuk memilih zona arah (ms).
const aimLatchOffset = Duration(milliseconds: 200);

const _sensorWatchdogDelay = Duration(seconds: 1);

/// Kunci Hive `app_cache` yang menyimpan tanggal (YYYY-MM-DD) pencetakan
/// achievement penalty terakhir, agar maksimal satu achievement per hari.
const _mintDayKey = 'penalty_block_day';

/// Kecepatan flick maksimum yang dinormalisasi (0-1).
const _maximumFlickSpeed = 1.0;

/// Kekuatan shake maksimum yang setara dengan kecepatan flick maksimum.
const _maximumFlickShake = 20.0;

/// State satu sesi Penalty Shootout.
///
/// Berisi tahap permainan, zona gol yang dipilih, kekuatan ayunan terakhir,
/// riwayat hasil tendangan, skor sesi, serta penanda mode demo, achievement
/// yang sudah dicetak, dan sudden death.
///
/// Objek ini immutable; perubahan dibuat lewat [PenaltyState.copyWith].
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

  /// Jumlah tendangan yang menjadi gol di sesi ini.
  int get goals =>
      results.where((result) => result.outcome == ShotOutcome.goal).length;

  /// Jumlah tendangan yang sudah dilakukan.
  int get taken => results.length;

  /// Sisa kesempatan sebelum sesi selesai (tidak pernah negatif).
  int get remaining => max(0, PenaltyRules.attempts - taken);

  /// Benar bila sesi sudah selesai.
  bool get isFinished => phase == Phase.finished;

  /// Benar bila sedang mengukur kekuatan ayunan.
  bool get isSwinging => phase == Phase.swinging;

  /// Salinan state dengan sebagian field diganti; `clearLast` dipakai untuk
  /// mengosongkan [last].
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

/// Provider sesi Penalty Shootout yang sedang berjalan.
///
/// `autoDispose`: sesi dibuang saat layar Penalty Shootout ditutup, sehingga
/// sensor akselerometer dan timer ikut berhenti. Efek samping: membuka stream
/// sensor (akselerometer) selama provider hidup.
final penaltyProvider =
    StateNotifierProvider.autoDispose<PenaltyNotifier, PenaltyState>(
  (ref) => PenaltyNotifier(ref),
);

/// Notifier mesin Penalty Shootout berbasis sensor akselerometer.
///
/// Tanggung jawabnya: membaca arah dan kekuatan ayunan HP, menentukan zona
/// gol, menghitung hasil tendangan lewat aturan di
/// `features/penalty_shootout/data/penalty_rules.dart`, menghitung skor
/// sesi, dan mencetak achievement + kartu harian saat sesi selesai dengan gol.
///
/// State-nya [PenaltyState]. Sensor, jam, dan sumber acak bisa diinjeksi
/// lewat parameter constructor agar logikanya bisa diuji tanpa perangkat.
///
/// Aturan §3.5: provider ini `autoDispose` dan `_mintAchievement` melakukan
/// `await`, sehingga setiap kali menyentuh `state` setelah `await` selalu
/// diperiksa `if (mounted)` terlebih dahulu — tanpa itu, provider yang
/// dibuang di tengah pencetakan akan error saat memperbarui state.
///
/// Efek samping: membuka subscription sensor akselerometer, menjalankan
/// timer ayunan/watchdog, dan (saat sesi berhasil) menulis blok
/// achievement ke rantai paspor (`passport_chain`), mencetak kartu
/// `penalty:<tanggal>`, serta menulis Hive `app_cache` `penalty_block_day`.
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

  /// Pilih zona secara manual saat sensor akselerometer tidak tersedia.
  ///
  /// Hanya bekerja bila mode demo aktif ([PenaltyState.demo]) dan fase masih
  /// [Phase.aiming]; selain itu diabaikan. Tanpa efek samping lain.
  void selectZone(KickZone zone) {
    if (!state.demo || state.phase != Phase.aiming) return;
    state = state.copyWith(zone: zone);
  }

  /// Gesture cadangan (geser) sebagai pengganti ayunan HP.
  ///
  /// `dx` dan `dy` dipakai sebagai arah (roll/pitch), `speed` dinormalisasi
  /// dari 0 (lambat) ke 1 (cepat) lalu dikonversi menjadi kekuatan shake
  /// dengan `_maximumFlickSpeed` dan `_maximumFlickShake`. Efek samping:
  /// menjalankan `_kick`, yang dapat mencetak achievement bila sesi selesai.
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

  /// Tendangkan dengan kekuatan demo saat sensor tidak tersedia.
  ///
  /// Hanya bekerja bila mode demo aktif ([PenaltyState.demo]) dan fase
  /// masih [Phase.aiming]. Kekuatan diambil dari `demoShot` (acak), lalu
  /// `_kick` dijalankan setelah jeda [peakSettleDelay]. Efek samping:
  /// pencetakan achievement bila sesi selesai.
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

  /// Lanjut ke percobaan berikutnya.
  ///
  /// Hanya bekerja bila fase saat ini [Phase.resolved]. Hasil tendangan
  /// terakhir baru dikosongkan di sini (bukan di [_kick]), supaya pengguna
  /// sempat melihat hasil. Tanpa efek samping.
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

  /// Mulai sesi baru dari awal.
  ///
  /// Membatalkan seluruh timer, mengembalikan state ke [Phase.aiming] dengan
  /// zona [KickZone.bottomMid], dan mempertahankan `last` sampai [next]
  /// membersihkannya. Mode demo aktif kembali bila sensor tidak pernah
  /// memberi data. Tanpa efek samping.
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

  /// Cetak achievement dan kartu harian bila sesi selesai dengan gol.
  ///
  /// Dilewati bila sesi sudah mencetak atau tidak ada gol sama sekali.
  /// Maksimal satu achievement per hari: tanggal (YYYY-MM-DD) disimpan di
  /// Hive `app_cache` dengan kunci `penalty_block_day`.
  ///
  /// Aturan §3.5: `await` di dalamnya diikuti pemeriksaan `mounted` sebelum
  /// `state` disentuh, karena provider ini `autoDispose`.
  ///
  /// Efek samping: menambah blok `achievement` ke rantai paspor
  /// (SQLite collection `passport_chain` + Hive `passport_chain`), mencetak
  /// kartu `penalty:<tanggal>`, lalu menulis Hive `app_cache`
  /// `penalty_block_day`.
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
