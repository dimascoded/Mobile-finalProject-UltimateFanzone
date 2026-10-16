import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/database/hive_service.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../penalty_shootout/data/penalty_rules.dart';
import '../data/blockchain.dart';
import '../data/chain_repository.dart';
import '../data/reflex_rules.dart';
import '../data/wallet_repository.dart';
import '../domain/club_card.dart';

final walletAddressProvider = FutureProvider<String>(
    (ref) => ref.watch(walletRepositoryProvider).getOrCreateAddress());

// ---------- Rantai blok Paspor ----------
class ChainNotifier extends StateNotifier<List<Block>> {
  ChainNotifier(this._repo) : super(_repo.load());
  final ChainRepository _repo;

  Future<Block> mint(
      String type, Map<String, dynamic> data, String owner) async {
    final block = Blockchain.next(state, type, data, owner);
    state = [...state, block];
    await _repo.save(state);
    return block;
  }

  /// Ganti seluruh rantai dan simpan ke Hive (dipakai pemulihan sinkronisasi).
  Future<void> replaceAll(List<Block> chain) async {
    state = chain;
    await _repo.save(state);
  }
}

final chainProvider = StateNotifierProvider<ChainNotifier, List<Block>>(
    (ref) => ChainNotifier(ref.watch(chainRepositoryProvider)));

final chainValidProvider =
    Provider<bool>((ref) => Blockchain.isValid(ref.watch(chainProvider)));

final stampsProvider = Provider<List<Block>>(
    (ref) => ref.watch(chainProvider).where((b) => b.type == 'stamp').toList());

// ---------- Kartu klub: satu blok 'card' per milestone ----------

/// Kartu terakhir yang berhasil di-mint, untuk dikonsumsi UI (Fase 3).
final lastEarnedCardProvider = StateProvider<ClubCard?>((ref) => null);

final cardMinterProvider = Provider<CardMinter>((ref) => CardMinter(ref));

/// Mencetak satu blok `card` per milestone.
///
/// Dedup membaca rantai itu sendiri (blok tipe `card` dengan `data['ref']` yang
/// sama), bukan flag terpisah, sehingga tetap berlaku setelah reinstall atau
/// pemulihan dari cloud. Mint memakai jalur yang sama dengan blok lain
/// (PoW + persist + sinkronisasi) lewat [ChainNotifier.mint]; tidak ada logika
/// mining yang diduplikasi.
class CardMinter {
  CardMinter(this._ref);
  final Ref _ref;

  /// Kembalikan kartu yang baru dicetak, atau null bila [ref] sudah pernah
  /// dicetak / blok gagal dibuat. Kegagalan tidak boleh mengganggu alur game,
  /// prediksi, atau stamp: semua error ditelan, di-log, dan jadi null.
  Future<ClubCard?> mintCard({
    required String source,
    required String ref,
  }) async {
    try {
      final already = _ref
          .read(chainProvider)
          .any((b) => b.type == 'card' && b.data['ref']?.toString() == ref);
      if (already) return null;

      final owner = await _ref.read(walletAddressProvider.future);
      final block = await _ref
          .read(chainProvider.notifier)
          .mint('card', {'source': source, 'ref': ref}, owner);

      final clubs = await _ref.read(clubsProvider.future);
      final card = cardFromBlock(block, [for (final c in clubs) c.key]);
      if (card != null) {
        _ref.read(lastEarnedCardProvider.notifier).state = card;
      }
      return card;
    } catch (e) {
      debugPrint('mintCard gagal (source=$source, ref=$ref): $e');
      return null;
    }
  }
}

// ---------- Cap stamp: wajib dekat stadion (atau mode demo) ----------
// Radius ini disepakati di rubrik: 800 m.
const stampRadiusMeters = 800.0;

/// Mode demo: melewati verifikasi GPS (dicatat gps_verified=false di blok).
final demoModeProvider = StateProvider<bool>((ref) => false);

/// Jarak (meter) dari posisi pengguna ke stadion klub favorit, atau null bila
/// GPS belum aktif / izin lokasi belum diberikan.
///
/// Sengaja TIDAK meminta izin sendiri: pemicunya tetap tombol "Cap stamp"
/// lewat confirmPermission, supaya rationale tampil sebelum permintaan OS.
final stampDistanceProvider = FutureProvider.autoDispose<int?>((ref) async {
  final club = ref.watch(favoriteClubProvider);
  if (club == null) return null;
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  final perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    return null;
  }
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
    return Geolocator.distanceBetween(
            pos.latitude, pos.longitude, club.lat, club.lng)
        .round();
  } catch (_) {
    return null;
  }
});

class StampNotifier extends StateNotifier<AsyncValue<String?>> {
  StampNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;

  Future<void> stamp(PlClub club) async {
    final demo = _ref.read(demoModeProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      // Semua dependensi dibaca SEBELUM await: ref tidak boleh dipakai
      // setelah provider di-dispose.
      final already = _ref.read(stampsProvider).any((b) =>
          b.data['club'] == club.key && b.data['stadium'] == club.stadium);
      if (already) throw Exception('Stamp ${club.stadium} sudah dimiliki');

      var distance = 0;
      if (!demo) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw Exception(
              'Lokasi GPS belum aktif. Nyalakan lokasi perangkat lalu coba lagi.');
        }
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          throw Exception('Izin lokasi ditolak');
        }
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        distance = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, club.lat, club.lng)
            .round();
        if (distance > stampRadiusMeters) {
          throw Exception(
              'Anda ${distance}m dari ${club.stadium}. Harus dalam ${stampRadiusMeters.round()}m.');
        }
      }
      final owner = await _ref.read(walletAddressProvider.future);
      final block = await _ref.read(chainProvider.notifier).mint(
          'stamp',
          {
            'club': club.key,
            'stadium': club.stadium,
            'gps_verified': !demo,
            'distance_m': distance,
          },
          owner);
      if (!demo) {
        await _ref
            .read(cardMinterProvider)
            .mintCard(source: 'stamp', ref: 'stamp:${club.key}');
      }
      return 'Stamp ${club.stadium} tercetak (catatan #${block.index})';
    });
    if (!mounted) return; // layar sudah ditutup
    state = result;
    if (!demo) _ref.invalidate(stampDistanceProvider);
  }
}

final stampProvider =
    StateNotifierProvider.autoDispose<StampNotifier, AsyncValue<String?>>(
        (ref) => StampNotifier(ref));

// ---------- Refleks Kiper ----------
class ReflexState {
  const ReflexState({
    this.score = 0,
    this.lives = reflexLives,
    this.combo = 0,
    this.saves = 0,
    this.level = 1,
    this.zone,
    this.running = false,
    this.gameOver = false,
    this.timeLimitMs = initialReflexTimeLimitMs,
    this.remainingMs = initialReflexTimeLimitMs,
    this.bestScore = 0,
  });

  final int score;
  final int lives;
  final int combo;
  final int saves;
  final int level;
  final KickZone? zone;
  final bool running;
  final bool gameOver;
  final int timeLimitMs;
  final int remainingMs;
  final int bestScore;

  double get ballProgress {
    if (timeLimitMs <= 0) return 1;
    return (1 - remainingMs / timeLimitMs).clamp(0.0, 1.0).toDouble();
  }

  ReflexState copyWith({
    int? score,
    int? lives,
    int? combo,
    int? saves,
    int? level,
    KickZone? zone,
    bool clearZone = false,
    bool? running,
    bool? gameOver,
    int? timeLimitMs,
    int? remainingMs,
    int? bestScore,
  }) =>
      ReflexState(
        score: score ?? this.score,
        lives: lives ?? this.lives,
        combo: combo ?? this.combo,
        saves: saves ?? this.saves,
        level: level ?? this.level,
        zone: clearZone ? null : (zone ?? this.zone),
        running: running ?? this.running,
        gameOver: gameOver ?? this.gameOver,
        timeLimitMs: timeLimitMs ?? this.timeLimitMs,
        remainingMs: remainingMs ?? this.remainingMs,
        bestScore: bestScore ?? this.bestScore,
      );
}

class ReflexNotifier extends StateNotifier<ReflexState> {
  ReflexNotifier(this._ref) : super(ReflexState(bestScore: _readBestScore()));

  final Ref _ref;
  final Random _rnd = Random();
  Timer? _ballTimer;
  DateTime? _ballStartedAt;

  static int _readBestScore() {
    try {
      return int.tryParse(HiveService.cache.get('reflex_best') ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void start() {
    _cancelTimer();
    final limit = timeLimitForLevel(1);
    state = ReflexState(
      running: true,
      zone: pickZone(_rnd, null),
      timeLimitMs: limit,
      remainingMs: limit,
      bestScore: state.bestScore,
    );
    _startBallTimer();
  }

  void tapZone(KickZone tappedZone) {
    if (!state.running || state.zone == null) return;
    if (tappedZone != state.zone) {
      _miss();
      return;
    }
    _save();
  }

  void _save() {
    _cancelTimer();
    final combo = comboAfterSave(state.combo);
    final saves = state.saves + 1;
    final level = levelForSaves(saves);
    final limit = timeLimitForLevel(level);
    final score = state.score + scoreForSave(combo);
    state = state.copyWith(
      score: score,
      lives: state.lives,
      combo: combo,
      saves: saves,
      level: level,
      zone: pickZone(_rnd, state.zone),
      running: true,
      gameOver: false,
      timeLimitMs: limit,
      remainingMs: limit,
      bestScore: score > state.bestScore ? score : state.bestScore,
    );
    _startBallTimer();
  }

  void _miss() {
    if (!state.running) return;
    _cancelTimer();
    final lives = livesAfterMiss(state.lives);
    if (lives == 0) {
      final bestScore =
          state.score > state.bestScore ? state.score : state.bestScore;
      state = state.copyWith(
        lives: 0,
        combo: comboAfterMiss(state.combo),
        running: false,
        gameOver: true,
        clearZone: true,
        remainingMs: 0,
        bestScore: bestScore,
      );
      _finishGame();
      return;
    }

    state = state.copyWith(
      lives: lives,
      combo: comboAfterMiss(state.combo),
      zone: pickZone(_rnd, state.zone),
      running: true,
      remainingMs: state.timeLimitMs,
    );
    _startBallTimer();
  }

  void _startBallTimer() {
    _ballStartedAt = DateTime.now();
    _ballTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted || !state.running) {
        _cancelTimer();
        return;
      }
      final elapsed = DateTime.now()
          .difference(_ballStartedAt ?? DateTime.now())
          .inMilliseconds;
      final remaining = state.timeLimitMs - elapsed;
      if (remaining <= 0) {
        _miss();
      } else {
        state = state.copyWith(remainingMs: remaining);
      }
    });
  }

  Future<void> _finishGame() async {
    final score = state.score;
    final saves = state.saves;
    final level = state.level;
    final bestScore = state.bestScore;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final shouldMint =
        score >= 100 && HiveService.cache.get('reflex_block_day') != today;

    final Future<String>? walletFuture =
        shouldMint ? _ref.read(walletAddressProvider.future) : null;
    final chain = shouldMint ? _ref.read(chainProvider.notifier) : null;

    await HiveService.cache.put('reflex_best', '$bestScore');
    if (!mounted || !shouldMint) return;

    final owner = await walletFuture!;
    if (!mounted) return;
    await chain!.mint(
      'achievement',
      {
        'game': 'Refleks Kiper',
        'score': score,
        'saves': saves,
        'level': level,
      },
      owner,
    );
    if (!mounted) return;
    await _ref
        .read(cardMinterProvider)
        .mintCard(source: 'reflex', ref: 'reflex:$today');
    if (!mounted) return;
    await HiveService.cache.put('reflex_block_day', today);
  }

  void _cancelTimer() {
    _ballTimer?.cancel();
    _ballTimer = null;
    _ballStartedAt = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}

final reflexProvider =
    StateNotifierProvider.autoDispose<ReflexNotifier, ReflexState>(
  (ref) => ReflexNotifier(ref),
);
