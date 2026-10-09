import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../football/data/football_repository.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/prediction_repository.dart';
import '../data/reveal_verifier.dart';

/// Prediksi aktif milik pengguna. Salt + skor disimpan LOKAL di Hive karena
/// belum boleh bocor sebelum kickoff. Yang masuk blockchain hanya commit-nya.
class PredictionStore {
  static const _key = 'score_predictions';

  /// Parse per-item (R2): satu prediksi rusak dilewati, bukan membuat seluruh
  /// daftar hilang karena `catch -> []`.
  List<Prediction> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    if (decoded is! List) return [];
    final out = <Prediction>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      try {
        out.add(Prediction.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        continue; // lewati item rusak, simpan yang lain
      }
    }
    return out;
  }

  Future<void> save(List<Prediction> list) => OfflineSyncDatabase.persist(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
}

final predictionStoreProvider = Provider((ref) => PredictionStore());

final _rnd = Random.secure();

String _newSalt() =>
    List.generate(16, (_) => _rnd.nextInt(16).toRadixString(16)).join();

/// Satu prediksi per matchId.
final predictionsProvider =
    StateNotifierProvider<PredictionsNotifier, List<Prediction>>(
  (ref) => PredictionsNotifier(ref.watch(predictionStoreProvider)),
);

class PredictionsNotifier extends StateNotifier<List<Prediction>> {
  PredictionsNotifier(this._store) : super(_store.load());

  final PredictionStore _store;

  Prediction? forMatch(int matchId) {
    final list = state.where((e) => e.matchId == matchId);
    return list.isEmpty ? null : list.first;
  }

  Future<void> put(Prediction p) async {
    state = [p, ...state.where((e) => e.matchId != p.matchId)];
    await _store.save(state);
  }

  /// Terapkan hasil merge sinkronisasi (S1): daftar gabungan dari server dan
  /// perangkat ini langsung disimpan ke Hive.
  Future<void> replaceAll(List<Prediction> list) async {
    state = list;
    await _store.save(state);
  }
}

class CommitResult {
  const CommitResult(this.prediction, this.alreadyCommitted);
  final Prediction prediction;
  final bool alreadyCommitted;
}

final predictionActionProvider = Provider((ref) => PredictionAction(ref));

class PredictionAction {
  PredictionAction(this._ref);
  final Ref _ref;

  /// Catat prediksi sebelum kickoff. Menolak perubahan bila:
  /// - kickoff sudah lewat
  /// - sudah ada commit untuk laga itu (prediksi tidak bisa diubah)
  Future<CommitResult> commit({
    required FootballMatch match,
    required int homeScore,
    required int awayScore,
  }) async {
    if (match.kickoffUtc.isBefore(DateTime.now().toUtc())) {
      throw Exception('Kickoff sudah lewat, prediksi ditutup');
    }
    // R3: data contoh bukan jadwal sungguhan, prediksi tidak dilakukan.
    final source = _ref.read(matchesProvider).valueOrNull?.source;
    if (source == DataSource.sample) {
      throw Exception('Data contoh: prediksi dinonaktifkan');
    }

    final notifier = _ref.read(predictionsProvider.notifier);
    final existing = notifier.forMatch(match.id);
    if (existing != null) return CommitResult(existing, true);

    final salt = _newSalt();
    final commit = Prediction.computeCommit(
      matchId: match.id,
      home: match.homeName,
      away: match.awayName,
      salt: salt,
    );
    final p = Prediction(
      matchId: match.id,
      homeScore: homeScore,
      awayScore: awayScore,
      salt: salt,
      commit: commit,
      createdAt: DateTime.now().toUtc(),
    );

    final walletFuture = _ref.read(walletAddressProvider.future);
    final chain = _ref.read(chainProvider.notifier);
    final owner = await walletFuture;

    // R2: mint harus selesai ditulis sebelum prediksi disimpan, supaya tidak ada
    // prediksi tanpa blok commit bila aplikasi tertutup di tengah jalan.
    await chain.mint(
      Prediction.blockTypeCommit,
      Prediction.commitData(
        matchId: match.id,
        home: match.homeName,
        away: match.awayName,
        commit: commit,
        at: p.createdAt,
      ),
      owner,
    );
    await notifier.put(p);
    return CommitResult(p, false);
  }
}

// ---------- Reveal + poin ----------

/// Status satu prediksi setelah reveal.
class SettledPrediction {
  const SettledPrediction({
    required this.prediction,
    required this.realHome,
    required this.realAway,
    required this.valid,
    required this.points,
  });

  final Prediction prediction;
  final int realHome, realAway;

  /// Hash terbuka sama dengan commit? Kalau tidak, prediksi tidak sah.
  final bool valid;
  final int points;
}

/// Prediksi yang laganya sudah selesai tapi blok result-nya belum ditulis.
final unsettledPredictionsProvider =
    Provider<List<({FootballMatch match, Prediction prediction})>>((ref) {
  final matches =
      ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final chain = ref.watch(chainProvider);
  final open = ref.watch(predictionsProvider);

  final out = <({FootballMatch match, Prediction prediction})>[];
  for (final m in matches) {
    if (!m.isFinished || !m.hasScore) continue;
    final p = open.where((e) => e.matchId == m.id).firstOrNull;
    if (p == null) continue;
    final already = chain.any(
        (b) => b.type == Prediction.blockTypeResult && b.data['match'] == m.id);
    if (already) continue;
    out.add((match: m, prediction: p));
  }
  return out;
});

/// Laga yang dibatalkan/diundur: tidak ada skor, jadi tidak bisa direveal.
bool isCancelledMatch(FootballMatch m) => isCancelledStatus(m.status);

/// Tulis blok result untuk prediksi yang sudah bisa direveal.
final settleActionProvider = Provider((ref) => SettleAction(ref));

class SettleAction {
  SettleAction(this._ref);
  final Ref _ref;

  /// Kembalikan poin yang didapat, atau null bila reveal tidak sah.
  ///
  /// R1: kebenaran dihitung dari BLOK RANTAI lewat [verifyReveal], bukan dari
  /// nilai yang tersimpan di Hive. Mengubah skor/salt/commit di Hive tidak
  /// membuat reveal jadi sah.
  Future<SettledPrediction?> settle(FootballMatch m, Prediction p) async {
    final chain = _ref.read(chainProvider);
    final verdict = verifyReveal(chain: chain, prediction: p, match: m);
    if (!verdict.valid || !m.hasScore) return null;

    final walletFuture = _ref.read(walletAddressProvider.future);
    final chainNotifier = _ref.read(chainProvider.notifier);
    final owner = await walletFuture;
    await chainNotifier.mint(
      Prediction.blockTypeResult,
      Prediction.resultData(
        matchId: p.matchId,
        salt: p.salt,
        predHome: p.homeScore,
        predAway: p.awayScore,
        realHome: m.homeScore!,
        realAway: m.awayScore!,
        points: verdict.points,
      ),
      owner,
    );
    return SettledPrediction(
      prediction: p,
      realHome: m.homeScore!,
      realAway: m.awayScore!,
      valid: true,
      points: verdict.points,
    );
  }
}

/// Poin dari blok result yang sudah tertulis di rantai.
final predictionPointsProvider = Provider<int>((ref) {
  final chain = ref.watch(chainProvider);
  var total = 0;
  for (final b in chain.where((b) => b.type == Prediction.blockTypeResult)) {
    final v = b.data['points'];
    if (v is num) total += v.toInt();
  }
  return total;
});
