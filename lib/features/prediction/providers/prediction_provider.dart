import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/prediction_repository.dart';

/// Prediksi aktif milik pengguna. Salt + skor disimpan LOKAL di Hive karena
/// belum boleh bocor sebelum kickoff. Yang masuk blockchain hanya commit-nya.
class PredictionStore {
  static const _key = 'score_predictions';

  List<Prediction> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Prediction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Prediction> list) => HiveService.cache.put(
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
  CommitResult commit({
    required FootballMatch match,
    required int homeScore,
    required int awayScore,
  }) {
    if (match.kickoffUtc.isBefore(DateTime.now().toUtc())) {
      throw Exception('Kickoff sudah lewat, prediksi ditutup');
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
    );

    final owner = _ref.read(walletAddressProvider).valueOrNull ?? 'local';
    _ref.read(chainProvider.notifier).mint(
          Prediction.blockTypeCommit,
          Prediction.commitData(
            matchId: match.id,
            home: match.homeName,
            away: match.awayName,
            commit: commit,
            at: DateTime.now().toUtc(),
          ),
          owner,
        );
    notifier.put(p);
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
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final chain = ref.watch(chainProvider);
  final open = ref.watch(predictionsProvider);

  final out = <({FootballMatch match, Prediction prediction})>[];
  for (final m in matches) {
    if (!m.isFinished || !m.hasScore) continue;
    final p = open.where((e) => e.matchId == m.id).firstOrNull;
    if (p == null) continue;
    final already = chain.any((b) =>
        b.type == Prediction.blockTypeResult && b.data['match'] == m.id);
    if (already) continue;
    out.add((match: m, prediction: p));
  }
  return out;
});

/// Tulis blok result untuk prediksi yang sudah bisa direveal.
final settleActionProvider = Provider((ref) => SettleAction(ref));

class SettleAction {
  SettleAction(this._ref);
  final Ref _ref;

  /// Kembalikan poin yang didapat, atau null bila reveal tidak sah.
  Future<SettledPrediction?> settle(FootballMatch m, Prediction p) async {
    final valid = Prediction.verify(
      matchId: p.matchId,
      home: m.homeName,
      away: m.awayName,
      salt: p.salt,
      expectedCommit: p.commit,
    );
    final points = valid
        ? scorePoints(
            predHome: p.homeScore,
            predAway: p.awayScore,
            realHome: m.homeScore!,
            realAway: m.awayScore!,
          )
        : 0;

    final owner = _ref.read(walletAddressProvider).valueOrNull ?? 'local';
    await _ref.read(chainProvider.notifier).mint(
          Prediction.blockTypeResult,
          Prediction.resultData(
            matchId: p.matchId,
            salt: p.salt,
            predHome: p.homeScore,
            predAway: p.awayScore,
            realHome: m.homeScore!,
            realAway: m.awayScore!,
            points: points,
          ),
          owner,
        );
    return SettledPrediction(
      prediction: p,
      realHome: m.homeScore!,
      realAway: m.awayScore!,
      valid: valid,
      points: points,
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
