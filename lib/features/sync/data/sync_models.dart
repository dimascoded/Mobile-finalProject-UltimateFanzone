import '../../away_day/data/away_day_repository.dart';
import '../../prediction/data/prediction_repository.dart';

/// Bentuk payload yang disepakati dengan server (server/sync.js).
///
/// Catatan: TIDAK ada `trip` di sini. Domain aplikasi sudah sepak bola,
/// jadi server memakai expenses / chain / predictions / feedback.
class SyncPayload {
  const SyncPayload({
    this.expenses = const [],
    this.chain = const [],
    this.predictions = const [],
    this.feedback,
  });

  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> chain;
  final List<Map<String, dynamic>> predictions;
  final Map<String, dynamic>? feedback;

  Map<String, dynamic> toJson() => {
        'expenses': expenses,
        'chain': chain,
        'predictions': predictions,
        if (feedback != null) 'feedback': feedback,
      };
}

Map<String, dynamic> expenseToJson(AwayDayExpense e) => {
      'id': e.id,
      'title': e.title,
      'amountGbp': e.amountGbp,
      'amountIdr': e.amountIdr,
      'category': e.category.name,
      'clubKey': e.clubKey,
      'date': e.date.toIso8601String(),
    };

/// Bentuk yang aman dikirim sebelum kickoff (S4).
///
/// Yang boleh keluar hanya `matchId`, `commit`, dan `createdAt`. Skor tebakan
/// dan `salt` TIDAK boleh ikut: kalau keduanya terkirim sebelum kickoff, orang
/// lain bisa menghitung sendiri `sha256(matchId|home|away|salt)` dari data
/// yang sama dan membandingkan dengan `commit`.
Map<String, dynamic> predictionCommitToJson(Prediction p) => {
      'matchId': p.matchId,
      'commit': p.commit,
      'createdAt': p.createdAt.toUtc().toIso8601String(),
    };

/// Bentuk lengkap, hanya boleh dipakai SETELAH blok result ditulis ke rantai,
/// karena saat itu salt dan skor sudah terbuka secara publik.
Map<String, dynamic> revealedPredictionToJson(Prediction p) => {
      'matchId': p.matchId,
      'homeScore': p.homeScore,
      'awayScore': p.awayScore,
      'salt': p.salt,
      'commit': p.commit,
      'createdAt': p.createdAt.toUtc().toIso8601String(),
    };

/// true kalau rantai lokal sudah punya blok result untuk laga ini.
bool hasResultBlock(List<Map<String, dynamic>> chain, int matchId) => chain
    .where((b) => b['type'] == Prediction.blockTypeResult)
    .any((b) => b['data'] is Map && (b['data']! as Map)['match'] == matchId);

/// Bentuk payload per prediksi (S4).
///
/// Kalau sudah ada blok result untuk laga itu, bentuk yang dikirim lengkap.
/// Tanpa blok result, hanya commit.
List<Map<String, dynamic>> predictionsToSync(
  List<Prediction> predictions,
  List<Map<String, dynamic>> chain,
) =>
    [
      for (final p in predictions)
        if (hasResultBlock(chain, p.matchId))
          revealedPredictionToJson(p)
        else
          predictionCommitToJson(p),
    ];

AwayDayExpense expenseFromJson(Map<String, dynamic> j) => AwayDayExpense(
      title: (j['title'] ?? '').toString(),
      amountGbp: (j['amountGbp'] as num?)?.toDouble() ?? 0,
      amountIdr: (j['amountIdr'] as num?)?.toDouble() ?? 0,
      category: AwayDayCategory.values.firstWhere(
        (c) => c.name == j['category'],
        orElse: () => AwayDayCategory.lainnya,
      ),
      date: DateTime.tryParse((j['date'] ?? '').toString()) ?? DateTime.now(),
      clubKey: j['clubKey']?.toString(),
    );

Prediction predictionFromJson(Map<String, dynamic> j) => Prediction(
      matchId: (j['matchId'] as num?)?.toInt() ?? 0,
      homeScore: (j['homeScore'] as num?)?.toInt() ?? 0,
      awayScore: (j['awayScore'] as num?)?.toInt() ?? 0,
      salt: (j['salt'] ?? '').toString(),
      commit: (j['commit'] ?? '').toString(),
    );

/// Gabungkan pengeluaran server dengan milik perangkat.
///
/// Aturan: entri dengan `id` sama TIDAK digandakan. Kalau id sama tapi isi
/// berbeda, versi lokal yang dipakai, karena usuario yang sedang memakai
/// perangkat ini dan server hanya salinan cadangan.
List<AwayDayExpense> mergeExpenses(
  List<AwayDayExpense> local,
  List<Map<String, dynamic>> remote,
) {
  final byId = <String, AwayDayExpense>{
    for (final r in remote) expenseFromJson(r).id: expenseFromJson(r),
  };
  final out = <AwayDayExpense>[...byId.values];
  for (final l in local) {
    final i = out.indexWhere((e) => e.id == l.id);
    if (i >= 0) {
      out[i] = l;
    } else {
      out.add(l);
    }
  }
  return out;
}

/// Sama seperti [mergeExpenses], satu prediksi per matchId.
///
/// Entri server yang belum punya `salt` (hanya commit, lihat
/// `predictionCommitToJson`) diabaikan: tanpa salt prediksi itu tidak akan
/// pernah bisa direveal, jadi mengadopsinya hanya menambah data yang tidak
/// bisa dipakai. Prediksi lokal selalu menang untuk matchId yang sama.
List<Prediction> mergePredictions(
  List<Prediction> local,
  List<Map<String, dynamic>> remote,
) {
  final byMatch = <int, Prediction>{};
  for (final r in remote) {
    try {
      final p = Prediction.fromJson(r);
      byMatch[p.matchId] = p;
    } catch (_) {
      continue; // commit-only atau rusak: lewati
    }
  }
  final out = <Prediction>[...byMatch.values];
  for (final l in local) {
    final i = out.indexWhere((p) => p.matchId == l.matchId);
    if (i >= 0) {
      out[i] = l;
    } else {
      out.add(l);
    }
  }
  return out;
}

/// Rantai blok TIDAK digabung dari server.
///
/// Blok di-mint dengan proof-of-work dan setiap blok menunjuk hash blok
/// sebelumnya, jadi rantai yang berasal dari server tidak bisa disambung ke
/// rantai lokal tanpa mining ulang. Rantai lokal tetap jadi sumber kebenaran;
/// server hanya cadangan yang di-push.
List<Map<String, dynamic>> chainToJson(Iterable<Map<String, dynamic>> chain) =>
    chain.toList();
