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
      'currencyCode': e.currencyCode,
      'amountForeign': e.amountForeign,
      'category': e.category.name,
      'clubKey': e.clubKey,
      'date': e.date.toIso8601String(),
    };

/// Bentuk commit-only: hanya `matchId`, `commit`, dan `createdAt` (tanpa skor
/// maupun `salt`).
///
/// Dipertahankan untuk kompatibilitas dan pengujian bentuk commit murni, tetapi
/// TIDAK lagi dipakai [predictionsToSync]. Baris cloud bersifat privat milik
/// pemiliknya (RLS `owner manages score predictions`), dan bukti integritas
/// commit-reveal ada di blok `prediction_commit` pada rantai — bukan pada baris
/// cloud. Menyimpan skor + `salt` di baris privat itu justru wajib supaya
/// prediksi yang belum ter-reveal tetap bisa dipulihkan setelah logout/reinstall.
Map<String, dynamic> predictionCommitToJson(Prediction p) => {
      'matchId': p.matchId,
      'commit': p.commit,
      'createdAt': p.createdAt.toUtc().toIso8601String(),
    };

/// Bentuk lengkap: `matchId`, skor tebakan, `salt`, `commit`, dan `createdAt`.
Map<String, dynamic> revealedPredictionToJson(Prediction p) => {
      'matchId': p.matchId,
      'homeScore': p.homeScore,
      'awayScore': p.awayScore,
      'salt': p.salt,
      'commit': p.commit,
      'createdAt': p.createdAt.toUtc().toIso8601String(),
    };

/// true kalau rantai lokal sudah punya blok result untuk laga ini.
///
/// Dipertahankan sebagai helper (mis. untuk pengujian atau logika lain), tetapi
/// sinkronisasi tidak lagi memakainya untuk memilih bentuk payload — lihat
/// [predictionsToSync].
bool hasResultBlock(List<Map<String, dynamic>> chain, int matchId) => chain
    .where((b) => b['type'] == Prediction.blockTypeResult)
    .any((b) => b['data'] is Map && (b['data']! as Map)['match'] == matchId);

/// Payload prediksi: SELALU bentuk penuh untuk SETIAP prediksi.
///
/// Baris `score_predictions` privat per pengguna (RLS: hanya pemilik yang boleh
/// baca/tulis), sedangkan bukti integritas commit-reveal ada di blok
/// `prediction_commit` pada rantai passport. Karena itu mengirim `homeScore`,
/// `awayScore`, dan `salt` tidak membocorkan rahasia ke pengguna lain, dan
/// justru diperlukan agar prediksi yang belum ter-reveal bisa dipulihkan setelah
/// logout/reinstall. Tidak lagi bergantung pada [hasResultBlock]; parameter
/// `chain` dipertahankan agar pemanggil tidak perlu berubah.
List<Map<String, dynamic>> predictionsToSync(
  List<Prediction> predictions,
  List<Map<String, dynamic>> chain,
) =>
    [for (final p in predictions) revealedPredictionToJson(p)];

AwayDayExpense expenseFromJson(Map<String, dynamic> j) => AwayDayExpense(
      title: (j['title'] ?? '').toString(),
      amountGbp: (j['amountGbp'] as num?)?.toDouble() ?? 0,
      amountIdr: (j['amountIdr'] as num?)?.toDouble() ?? 0,
      currencyCode: j['currencyCode'] as String? ?? 'GBP',
      amountForeign: (j['amountForeign'] as num?)?.toDouble() ??
          (j['amountGbp'] as num?)?.toDouble() ??
          0,
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

/// Koleksi cloud untuk prediksi skor (deletion lewat hapus baris langsung,
/// sebab `sync_tombstones` hanya menerima `away_day_expenses`).
const kPredictionCollection = 'score_predictions';

/// Koleksi cloud untuk pengeluaran (deletion lewat `sync_tombstones`).
const kExpenseCollection = 'away_day_expenses';

/// Pisahkan antrean penghapusan lokal per koleksi.
///
/// `score_predictions` tidak bisa memakai `sync_tombstones` (CHECK constraint di
/// schema hanya mengizinkan `away_day_expenses`), jadi id laga dikembalikan
/// terpisah untuk dihapus langsung dari tabelnya.
({Set<int> predictionMatchIds, List<({String collection, String itemId})>
    expenseDeletions}) partitionDeletions(
  List<({String collection, String itemId})> deletions,
) {
  final matchIds = <int>{};
  final expenseDeletions = <({String collection, String itemId})>[];
  for (final d in deletions) {
    if (d.collection == kPredictionCollection) {
      final id = int.tryParse(d.itemId);
      if (id != null) matchIds.add(id);
    } else if (d.collection == kExpenseCollection) {
      expenseDeletions.add(d);
    }
  }
  return (predictionMatchIds: matchIds, expenseDeletions: expenseDeletions);
}

/// Sama seperti [mergeExpenses], satu prediksi per matchId.
///
/// Baris cloud kini membawa `salt` dan `commit`, jadi [Prediction.fromJson]
/// bisa memulihkannya — termasuk prediksi yang belum ter-reveal. Baris lama yang
/// masih commit-only (tanpa `salt`) TETAP dilewati: tanpa salt prediksi itu tidak
/// akan pernah bisa direveal, jadi mengadopsinya hanya menambah data yang tidak
/// bisa dipakai. Prediksi lokal selalu menang untuk matchId yang sama.
///
/// [deletedMatchIds] berisi matchId yang baru saja dihapus pengguna. Baris remote
/// (sisa cadangan yang belum sempat terhapus) maupun prediksi lokal untuk id itu
/// TIDAK dimasukkan, sehingga prediksi yang dihapus tidak "bangkit" lagi dan
/// tidak ikut dikirim ulang.
List<Prediction> mergePredictions(
  List<Prediction> local,
  List<Map<String, dynamic>> remote, {
  Set<int> deletedMatchIds = const {},
}) {
  final byMatch = <int, Prediction>{};
  for (final r in remote) {
    try {
      final p = Prediction.fromJson(r);
      if (deletedMatchIds.contains(p.matchId)) continue;
      byMatch[p.matchId] = p;
    } catch (_) {
      continue; // commit-only lama atau baris rusak: lewati
    }
  }
  final out = <Prediction>[...byMatch.values];
  for (final l in local) {
    if (deletedMatchIds.contains(l.matchId)) continue;
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
