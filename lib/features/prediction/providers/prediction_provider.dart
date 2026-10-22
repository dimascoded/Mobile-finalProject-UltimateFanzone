import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../football/data/football_repository.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/prediction_rank.dart';
import '../data/prediction_repository.dart';
import '../data/reveal_verifier.dart';

/// Prediksi aktif milik pengguna. Salt + skor disimpan LOKAL di Hive karena
/// belum boleh bocor sebelum kickoff. Yang masuk blockchain hanya commit-nya.
///
/// Key Hive `app_cache` yang dipakai adalah `score_predictions`, dan
/// penyimpanan lewat [OfflineSyncDatabase.persist] sehingga juga menjadi baris
/// di SQLite `sync_documents` collection `score_predictions` (revisi naik tiap
/// penulisan). Kunci ini termasuk [AuthRepository.userDataKeys], jadi ikut
/// terhapus saat logout.
class PredictionStore {
  static const collection = 'score_predictions';
  static const _key = collection;

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

  /// Simpan seluruh daftar prediksi ke Hive `score_predictions` dan SQLite
  /// collection `score_predictions`.
  Future<void> save(List<Prediction> list) => OfflineSyncDatabase.persist(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
}

/// Penyedia tunggal [PredictionStore].
final predictionStoreProvider = Provider((ref) => PredictionStore());

/// Pembuat salt acak yang kuat (16 karakter hex) untuk komitmen prediksi.
///
/// Menghasilkan bytes acak dari `Random.secure()` sehingga salt tidak bisa
/// ditebak sebelum kickoff.
final _rnd = Random.secure();

/// Hasilkan salt baru sebagai 16 karakter hex.
String _newSalt() =>
    List.generate(16, (_) => _rnd.nextInt(16).toRadixString(16)).join();

/// Prediksi milik pengguna (satu prediksi per matchId).
///
/// Provider ini dipakai lintas layar (Match Center, prediksi, sinkronisasi),
/// jadi bukan `autoDispose`; sumber penyimpanan ada di [PredictionsNotifier].
final predictionsProvider =
    StateNotifierProvider<PredictionsNotifier, List<Prediction>>(
  (ref) => PredictionsNotifier(ref.watch(predictionStoreProvider)),
);

/// Prediksi aktif milik pengguna.
///
/// State-nya `List<Prediction>`; hanya satu prediksi per `matchId`. Data
/// disimpan di Hive `app_cache` (kunci `score_predictions`) dan SQLite
/// collection `score_predictions`.
///
/// Notifier tidak `autoDispose` (prediksi dipakai lintas layar), jadi tidak
/// wajib cek `mounted` setelah `await` (aturan §3.5 hanya berlaku untuk
/// notifier `autoDispose`).
class PredictionsNotifier extends StateNotifier<List<Prediction>> {
  PredictionsNotifier(this._store) : super(_store.load());

  final PredictionStore _store;

  /// Ambil prediksi untuk satu laga, atau null bila belum ada.
  ///
  /// Fungsi murni, tanpa efek samping.
  Prediction? forMatch(int matchId) {
    final list = state.where((e) => e.matchId == matchId);
    return list.isEmpty ? null : list.first;
  }

  /// Simpan atau timpa prediksi untuk satu laga.
  ///
  /// Baris lama untuk `matchId` yang sama dibuang, lalu prediksi baru
  /// dimasukkan di depan. Efek samping: menulis Hive `score_predictions` dan
  /// SQLite collection `score_predictions`.
  Future<void> put(Prediction p) async {
    state = [p, ...state.where((e) => e.matchId != p.matchId)];
    await _store.save(state);
  }

  /// Hapus satu prediksi yang tidak lagi bisa dibuka atau diprediksi ulang.
  ///
  /// Hanya boleh bila kickoff sudah lewat (atau jadwalnya tidak diketahui,
  /// [kickoffUtc] null). Laga yang belum kickoff masih bisa ditebak, jadi
  /// penghapusan ditolak dan prediksi tetap ada. [nowUtc] diinjeksi supaya
  /// perilakunya bisa diuji tanpa jam asli.
  ///
  /// Poin dan kartu yang sudah didapat TIDAK terpengaruh: keduanya hidup di
  /// blok result/card, bukan di baris prediksi ini.
  ///
  /// Efek samping: menambah antrean penghapusan di SQLite (collection
  /// `score_predictions`) lewat [OfflineSyncDatabase.queueDeletion], lalu
  /// menulis ulang daftar ke Hive `score_predictions` dan SQLite collection
  /// `score_predictions`. Baris cloud ikut terhapus pada sinkronisasi
  /// berikutnya.
  Future<bool> remove(
    int matchId, {
    required DateTime? kickoffUtc,
    required DateTime nowUtc,
  }) async {
    if (kickoffUtc != null && !kickoffUtc.isBefore(nowUtc)) return false;

    final before = state.length;
    state = state.where((e) => e.matchId != matchId).toList();
    if (state.length == before) return false;

    // Antre agar baris cloud ikut terhapus pada sinkronisasi berikutnya
    // (mekanisme yang sama seperti pengeluaran Away Day).
    await OfflineSyncDatabase.queueDeletion(
      PredictionStore.collection,
      '$matchId',
    );
    await _store.save(state);
    return true;
  }

  /// Terapkan hasil merge sinkronisasi (S1): daftar gabungan dari server dan
  /// perangkat ini langsung disimpan ke Hive.
  ///
  /// Efek samping: menulis Hive `score_predictions` dan SQLite collection
  /// `score_predictions`.
  Future<void> replaceAll(List<Prediction> list) async {
    state = list;
    await _store.save(state);
  }
}

/// Hasil commit prediksi: prediksi yang tercatat, dan apakah laga itu sudah
/// pernah diprediksi sebelumnya (jadi tidak ada commit baru).
class CommitResult {
  const CommitResult(this.prediction, this.alreadyCommitted);
  final Prediction prediction;
  final bool alreadyCommitted;
}

/// Aksi commit prediksi skor (dipakai layar form prediksi).
final predictionActionProvider = Provider((ref) => PredictionAction(ref));

/// Penulis blok commit prediksi ke rantai paspor.
///
/// Aksi ini memastikan bahwa satu laga hanya pernah punya SATU blok commit.
/// Bila rantai sudah punya commit tapi data tebakan (salt) tidak ada di
/// perangkat ini, commit baru tidak akan pernah bisa dibuka; oleh karena itu
/// [commit] menolak dan meminta pengguna menyinkronkan dulu.
///
/// Notifier/aksi ini tidak `autoDispose`, jadi tidak wajib cek `mounted`
/// setelah `await` (aturan §3.5 hanya berlaku untuk notifier `autoDispose`).
class PredictionAction {
  PredictionAction(this._ref);
  final Ref _ref;

  /// Catat prediksi sebelum kickoff. Menolak perubahan bila:
  /// - kickoff sudah lewat
  /// - sudah ada commit untuk laga itu (prediksi tidak bisa diubah)
  /// - sumber data adalah data contoh (R3)
  ///
  /// Bila laga itu sudah pernah diprediksi, metode ini mengembalikan
  /// [CommitResult] dengan `alreadyCommitted: true` dan tidak menambah blok
  /// baru. Bila rantai sudah punya blok commit untuk laga itu tetapi data
  /// tebakan (salt) tidak ada di perangkat ini, metode melempar galat agar
  /// pengguna menyinkronkan dulu.
  ///
  /// Efek samping: menambah blok commit ke rantai paspor (SQLite collection
  /// `passport_chain` + Hive `passport_chain`) dan menyimpan prediksi ke Hive
  /// `score_predictions` + SQLite collection `score_predictions`. Blok commit
  /// ditulis lebih dulu (R2) supaya tidak ada prediksi tanpa blok commit bila
  /// aplikasi ditutup di tengah jalan.
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

    // Jangan pernah mining blok commit kedua untuk laga yang sama. Kalau rantai
    // sudah punya commit tapi data tebakan (salt) tidak ada di perangkat ini,
    // prediksi baru tidak akan pernah bisa dibuka: verifyReveal selalu memakai
    // blok commit PERTAMA (findCommitBlock), yang commit-nya dibuat dengan salt
    // lama. Sinkronkan dulu agar prediksi asli (beserta salt-nya) kembali.
    final chainBlocks = _ref.read(chainProvider);
    if (findCommitBlock(chainBlocks, match.id) != null) {
      throw Exception(
          'Laga ini sudah pernah diprediksi dan tebakan tidak bisa dibuat '
          'ulang.');
    }

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
///
/// Dibentuk oleh [SettleAction.settleDetailed] ketika skor resmi tersedia
/// dan blok result berhasil ditulis. [points] adalah poin yang dihitung dari
/// kecocokan tebakan, sedangkan [rankUp] terisi bila total poin menyeberangi
/// peringkat baru.
class SettledPrediction {
  const SettledPrediction({
    required this.prediction,
    required this.realHome,
    required this.realAway,
    required this.valid,
    required this.points,
    this.rankUp,
  });

  final Prediction prediction;
  final int realHome, realAway;

  /// Hash terbuka sama dengan commit? Kalau tidak, prediksi tidak sah.
  final bool valid;
  final int points;
  final PredictionRank? rankUp;
}

/// Prediksi yang laganya sudah selesai tapi blok result-nya belum ditulis.
///
/// Provider turunan dari [matchesProvider], [chainProvider], dan
/// [predictionsProvider]: memasangkan setiap prediksi pengguna dengan laga
/// berstatus selesai + punya skor yang belum punya blok result di rantai.
/// Dipakai layar untuk menawarkan reveal. Tanpa efek samping.
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
///
/// Fungsi murni, tanpa efek samping; hanya delegasi ke
/// [isCancelledStatus] pada status laga.
bool isCancelledMatch(FootballMatch m) => isCancelledStatus(m.status);

/// Tulis blok result untuk prediksi yang sudah bisa direveal.
final settleActionProvider = Provider((ref) => SettleAction(ref));

/// Penulis blok result (reveal) ke rantai paspor.
///
/// Kebenaran diverifikasi terhadap rantai blockchain, bukan terhadap nilai
/// yang tersimpan di Hive (aturan R1); mengubah data lokal tidak membuat
/// reveal jadi sah. Setelah reveal sukses, kartu milestone (skor tepat atau
/// arah hasil sesuai) dan kartu peringkat bisa ikut tercetak.
///
/// Aksi ini tidak `autoDispose`, jadi tidak wajib cek `mounted` setelah
/// `await` (aturan §3.5 hanya berlaku untuk notifier `autoDispose`).
class SettleAction {
  SettleAction(this._ref);
  final Ref _ref;

  /// Kembalikan poin yang didapat, atau null bila reveal tidak sah.
  ///
  /// R1: kebenaran dihitung dari BLOK RANTAI lewat [verifyReveal], bukan dari
  /// nilai yang tersimpan di Hive. Mengubah skor/salt/commit di Hive tidak
  /// membuat reveal jadi sah.
  ///
  /// Pembungkus tipis [settleDetailed] supaya pemanggil lama tetap kompil.
  Future<SettledPrediction?> settle(FootballMatch m, Prediction p) async =>
      (await settleDetailed(m, p)).settled;

  /// Versi rinci [settle]: selalu mengembalikan alasan saat gagal, sehingga UI
  /// bisa menjelaskan kenapa sebuah prediksi belum bisa dibuka.
  ///
  /// Efek samping bila reveal sah: menambah blok `result` ke rantai paspor
  /// (SQLite collection `passport_chain` + Hive `passport_chain`), bisa juga
  /// menambah kartu milestone (`prediction:<matchId>`) dan kartu peringkat
  /// (`rank:<key>`) lewat [CardMinter.mintCard].
  Future<({SettledPrediction? settled, String? reason, String? debug})>
      settleDetailed(
    FootballMatch m,
    Prediction p,
  ) async {
    if (!m.hasScore) {
      return (
        settled: null,
        reason: 'Skor resmi belum tersedia',
        debug: null
      );
    }

    final chain = _ref.read(chainProvider);
    final verdict = verifyReveal(chain: chain, prediction: p, match: m);
    if (!verdict.valid) {
      return (settled: null, reason: verdict.reason, debug: verdict.debug);
    }

    try {
      final pointsBefore = _ref.read(predictionPointsProvider);
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
      // Kartu milestone hanya bila tebakan benar: skor tepat atau arah hasil
      // (menang/seri/kalah) sesuai, sama seperti bonus arah di scorePoints.
      final exact = p.homeScore == m.homeScore! && p.awayScore == m.awayScore!;
      final outcomeMatches = p.homeScore.compareTo(p.awayScore) ==
          m.homeScore!.compareTo(m.awayScore!);
      if (exact || outcomeMatches) {
        await _ref.read(cardMinterProvider).mintCard(
              source: 'prediction',
              ref: 'prediction:${p.matchId}',
            );
      }
      final pointsAfter = pointsBefore + verdict.points;
      final crossedRanks = ranksCrossed(pointsBefore, pointsAfter);
      for (final rank in crossedRanks) {
        try {
          await _ref.read(cardMinterProvider).mintCard(
                source: 'rank',
                ref: 'rank:${rank.key}',
              );
        } catch (_) {
          // Rank rewards must not interrupt a valid settle.
        }
      }
      return (
        settled: SettledPrediction(
          prediction: p,
          realHome: m.homeScore!,
          realAway: m.awayScore!,
          valid: true,
          points: verdict.points,
          rankUp: crossedRanks.isEmpty ? null : crossedRanks.last,
        ),
        reason: null,
        debug: null,
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      return (
        settled: null,
        reason: 'Gagal menulis blok: $message',
        debug: null
      );
    }
  }
}

/// Poin dari blok result yang sudah tertulis di rantai.
///
/// Provider turunan dari [chainProvider]: menjumlahkan `data['points']` dari
/// setiap blok bertipe result. Poin hidup di blockchain, bukan di baris
/// prediksi, sehingga tetap ada walau prediksi dihapus.
/// Tanpa efek samping.
final predictionPointsProvider = Provider<int>((ref) {
  final chain = ref.watch(chainProvider);
  var total = 0;
  for (final b in chain.where((b) => b.type == Prediction.blockTypeResult)) {
    final v = b.data['points'];
    if (v is num) total += v.toInt();
  }
  return total;
});
