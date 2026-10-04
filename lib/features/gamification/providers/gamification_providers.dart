import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../football/data/models.dart';
import '../data/blockchain.dart';
import '../data/chain_repository.dart';
import '../data/wallet_repository.dart';

final walletAddressProvider = FutureProvider<String>(
    (ref) => ref.watch(walletRepositoryProvider).getOrCreateAddress());

// ---------- Rantai blok Paspor ----------
class ChainNotifier extends StateNotifier<List<Block>> {
  ChainNotifier(this._repo) : super(_repo.load());
  final ChainRepository _repo;

  Future<Block> mint(String type, Map<String, dynamic> data, String owner) async {
    final block = Blockchain.next(state, type, data, owner);
    state = [...state, block];
    await _repo.save(state);
    return block;
  }
}

final chainProvider = StateNotifierProvider<ChainNotifier, List<Block>>(
    (ref) => ChainNotifier(ref.watch(chainRepositoryProvider)));

final chainValidProvider =
    Provider<bool>((ref) => Blockchain.isValid(ref.watch(chainProvider)));

final stampsProvider = Provider<List<Block>>(
    (ref) => ref.watch(chainProvider).where((b) => b.type == 'stamp').toList());

// ---------- Cap stamp: wajib dekat landmark (atau mode demo) ----------
const stampRadiusMeters = 500.0;

/// Mode demo: melewati verifikasi GPS (dicatat gps_verified=false di blok).
final demoModeProvider = StateProvider<bool>((ref) => false);

class StampNotifier extends StateNotifier<AsyncValue<String?>> {
  StampNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;

  Future<void> stamp(PlClub club) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final demo = _ref.read(demoModeProvider);
      final already = _ref.read(stampsProvider).any(
          (b) => b.data['club'] == club.key && b.data['landmark'] == club.stadium);
      if (already) throw Exception('Stamp ${club.stadium} sudah dimiliki');

      var distance = 0;
      if (!demo) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          throw Exception('Izin lokasi ditolak');
        }
        final pos = await Geolocator.getCurrentPosition();
        distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, club.lat, club.lng).round();
        if (distance > stampRadiusMeters) {
          throw Exception(
              'Anda ${distance}m dari ${club.stadium}. Harus dalam ${stampRadiusMeters.round()}m.');
        }
      }
      final owner = await _ref.read(walletAddressProvider.future);
      final block = await _ref.read(chainProvider.notifier).mint('stamp', {
        'club': club.key,
        'landmark': club.stadium,
        'gps_verified': !demo,
        'distance_m': distance,
      }, owner);
      return 'Stamp ${club.stadium} tercetak (blok #${block.index})';
    });
    if (!mounted) return; // layar sudah ditutup
    state = result;
  }
}

final stampProvider =
    StateNotifierProvider.autoDispose<StampNotifier, AsyncValue<String?>>(
        (ref) => StampNotifier(ref));

// ---------- Mini game: tekan objek bergerak acak selama 15 detik ----------
class GameState {
  const GameState({
    this.score = 0,
    this.secondsLeft = 15,
    this.running = false,
    this.finished = false,
    this.dx = 0,
    this.dy = 0,
  });
  final int score, secondsLeft;
  final bool running, finished;
  final double dx, dy; // Alignment -1..1

  static const winScore = 10;
  bool get won => finished && score >= winScore;

  GameState copyWith({int? score, int? secondsLeft, bool? running, bool? finished, double? dx, double? dy}) =>
      GameState(
        score: score ?? this.score,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        running: running ?? this.running,
        finished: finished ?? this.finished,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
      );
}

class GameNotifier extends StateNotifier<GameState> {
  GameNotifier(this._ref) : super(const GameState());
  final Ref _ref;
  final _rnd = Random();
  Timer? _countdown, _mover;

  void start() {
    _cancel();
    state = const GameState(running: true);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.secondsLeft - 1;
      if (left <= 0) {
        _finish();
      } else {
        state = state.copyWith(secondsLeft: left);
      }
    });
    _mover = Timer.periodic(const Duration(milliseconds: 900), (_) => _move());
    _move();
  }

  void tap() {
    if (!state.running) return;
    state = state.copyWith(score: state.score + 1);
    _move();
  }

  void _move() => state = state.copyWith(
        dx: _rnd.nextDouble() * 1.8 - 0.9,
        dy: _rnd.nextDouble() * 1.8 - 0.9,
      );

  Future<void> _finish() async {
    _cancel();
    final score = state.score;
    state = state.copyWith(secondsLeft: 0, running: false, finished: true);
    if (state.won) {
      // Ambil dependensi SEBELUM await: ref tidak boleh dipakai setelah dispose.
      final walletFuture = _ref.read(walletAddressProvider.future);
      final chain = _ref.read(chainProvider.notifier);
      final owner = await walletFuture;
      await chain.mint('achievement', {'game': 'Speed Tapper', 'score': score}, owner);
    }
  }

  void _cancel() {
    _countdown?.cancel();
    _mover?.cancel();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }
}

final gameProvider = StateNotifierProvider.autoDispose<GameNotifier, GameState>(
    (ref) => GameNotifier(ref));
