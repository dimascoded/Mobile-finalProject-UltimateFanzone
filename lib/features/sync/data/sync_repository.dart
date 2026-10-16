import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../away_day/data/away_day_repository.dart';
import '../../gamification/data/blockchain.dart';
import '../../prediction/data/prediction_repository.dart';
import 'chain_reconcile.dart';
import 'sync_models.dart';

/// Hasil satu siklus sinkronisasi.
class SyncResult {
  const SyncResult({
    this.pushedExpenses = 0,
    this.pushedChain = 0,
    this.pushedPredictions = 0,
    this.mergedExpenses = 0,
    this.mergedPredictions = 0,
    List<AwayDayExpense>? expenses,
    List<Prediction>? predictions,
    List<Map<String, dynamic>>? remoteChain,
    this.chainOutcome,
    this.droppedLocalBlocks = 0,
    this.adoptedChain = false,
    this.unauthorized = false,
  })  : // S1: kembalikan daftar hasil merge, bukan hanya jumlah, supaya
        // SyncNotifier benar-benar menerapkannya ke Hive.
        expenses = expenses ?? const [],
        predictions = predictions ?? const [],
        remoteChain = remoteChain ?? const [];

  final int pushedExpenses, pushedChain, pushedPredictions;
  final int mergedExpenses, mergedPredictions;

  /// Daftar gabungan yang harus ditulis ke Hive.
  final List<AwayDayExpense> expenses;
  final List<Prediction> predictions;

  /// Rantai dari server, untuk diperiksa [Blockchain.canAdoptRemote].
  final List<Map<String, dynamic>> remoteChain;

  /// Keputusan rekonsiliasi cloud (hanya diisi jalur Supabase).
  final ChainOutcome? chainOutcome;

  /// Blok lokal yang tidak bisa digabung setelah adopsi cloud.
  final int droppedLocalBlocks;

  /// Rantai server berhasil diadopsi (S2).
  final bool adoptedChain;

  /// true = server menjawab 401, sesi harus diakhiri (S3).
  final bool unauthorized;
}

/// Galat sinkronisasi yang membawa pesan ramah dan penanda 401 (S3).
class SyncException implements Exception {
  SyncException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

/// Kirim data lokal ke server, lalu tarik data server untuk digabung.
///
/// Mode offline-first: aplikasi tetap menulis ke Hive lebih dulu, jadi
/// [SyncRepository.sync] gagal (tidak ada internet) tidak menghapus data lokal.
class SyncRepository {
  SyncRepository(
    this._dio,
    this._auth, {
    String baseUrl = '',
    Future<String?> Function()? tokenLoader,
  }) : _baseUrl = baseUrl {
    // Token diambil lewat [tokenLoader] kalau diberi, supaya _guard dan
    // pemeriksa token bisa diuji tanpa menyentuh secure storage.
    _tokenLoader = tokenLoader ?? _auth.currentToken;
  }

  final Dio _dio;
  final AuthRepository _auth;
  final String _baseUrl;
  late final Future<String?> Function() _tokenLoader;

  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    List<({String collection, String itemId})> deletions = const [],
    Map<String, dynamic>? feedback,
  }) async {
    if (AppConfig.supabaseConfigured) {
      return _syncSupabase(
        expenses: expenses,
        chain: chain,
        predictions: predictions,
        deletions: deletions,
      );
    }
    if (_baseUrl.isEmpty) {
      // Cloud belum dikonfigurasi: jangan sentuh Hive, kembalikan data lokal
      // apa adanya supaya `replaceAll` hanya menulis ulang data yang sama.
      return SyncResult(
        pushedExpenses: expenses.length,
        pushedChain: chain.length,
        pushedPredictions: predictions.length,
        mergedExpenses: expenses.length,
        mergedPredictions: predictions.length,
        expenses: expenses,
        predictions: predictions,
      );
    }

    final token = await _tokenLoader();
    if (token == null || token.isEmpty) {
      throw SyncException('Belum login. Masuk dulu sebelum mencadangkan.');
    }
    final headers = {'Authorization': 'Bearer $token'};
    final payload = SyncPayload(
      expenses: expenses.map(expenseToJson).toList(),
      chain: chainToJson(chain),
      // Prediksi dikirim dalam bentuk PENUH (skor + salt) untuk setiap laga.
      // Baris prediksi privat per pengguna, dan bukti integritas commit-reveal
      // tetap blok `prediction_commit` di rantai, bukan baris cloud.
      predictions: predictionsToSync(predictions, chain),
      feedback: feedback,
    );

    // 1. Push. Kalau gagal, data lokal tetap utuh karena Hive sudah menyimpannya.
    final body = await _guard(() => _dio.post(
          '$_baseUrl/sync',
          data: payload.toJson(),
          options: Options(headers: headers),
        ));

    // 2. Pull.
    final remote = await _guard(() => _dio.get(
          '$_baseUrl/sync',
          options: Options(headers: headers),
        ));

    final remoteExpenses = _listOfMaps(remote['expenses']);
    final remotePredictions = _listOfMaps(remote['predictions']);
    final remoteChain = _listOfMaps(remote['chain']);

    // S1: hitung daftar gabungan, dikembalikan untuk ditulis ke Hive.
    final mergedExpenses = mergeExpenses(expenses, remoteExpenses);
    final mergedPredictions = mergePredictions(predictions, remotePredictions);

    return SyncResult(
      pushedExpenses: _countOf(body['expenses']),
      pushedChain: _countOf(body['chain']),
      pushedPredictions: _countOf(body['predictions']),
      mergedExpenses: mergedExpenses.length,
      mergedPredictions: mergedPredictions.length,
      expenses: mergedExpenses,
      predictions: mergedPredictions,
      remoteChain: remoteChain,
    );
  }

  Future<SyncResult> _syncSupabase({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    required List<({String collection, String itemId})> deletions,
  }) async {
    final client = supa.Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw SyncException('Masuk ke akun dulu sebelum mencadangkan.');
    }

    if (deletions.isNotEmpty) {
      await client.from('sync_tombstones').upsert(
        [
          for (final deletion in deletions)
            {
              'user_id': userId,
              'collection': deletion.collection,
              'item_id': deletion.itemId,
            },
        ],
        onConflict: 'user_id,collection,item_id',
        ignoreDuplicates: true,
      );
    }
    final remoteTombstones = await _selectAll(
      client,
      'sync_tombstones',
      userId,
    );
    final deletedExpenseIds = remoteTombstones
        .where((row) => row['collection'] == 'away_day_expenses')
        .map((row) => row['item_id'] as String)
        .toSet();
    if (deletedExpenseIds.isNotEmpty) {
      await client
          .from('away_day_expenses')
          .delete()
          .eq('user_id', userId)
          .inFilter('id', deletedExpenseIds.toList());
    }

    final remoteExpenseRows =
        await _selectAll(client, 'away_day_expenses', userId);
    final normalizedRemoteExpenses = <Map<String, dynamic>>[
      for (final row in remoteExpenseRows)
        if (!deletedExpenseIds.contains(row['id']))
          {
            'id': row['id'],
            'title': row['title'],
            'amountGbp': row['amount_gbp'],
            'amountIdr': row['amount_idr'],
            'currencyCode': row['currency_code'] ?? 'GBP',
            'amountForeign': row['amount_foreign'] ?? row['amount_gbp'],
            'category': row['category'],
            'clubKey': row['club_key'],
            'date': row['created_at'],
          },
    ];
    final activeExpenses =
        expenses.where((e) => !deletedExpenseIds.contains(e.id)).toList();
    final mergedExpenses =
        mergeExpenses(activeExpenses, normalizedRemoteExpenses);
    if (mergedExpenses.isNotEmpty) {
      await client.from('away_day_expenses').upsert(
        [
          for (final expense in mergedExpenses)
            {
              'user_id': userId,
              'id': expense.id,
              'title': expense.title,
              'amount_gbp': expense.amountGbp,
              'amount_idr': expense.amountIdr,
              'currency_code': expense.currencyCode,
              'amount_foreign': expense.amountForeign,
              'category': expense.category.name,
              'club_key': expense.clubKey,
              'created_at': expense.date.toIso8601String(),
            },
        ],
        onConflict: 'user_id,id',
      );
    }

    final remotePredictionRows =
        await _selectAll(client, 'score_predictions', userId);
    final normalizedRemotePredictions = <Map<String, dynamic>>[
      for (final row in remotePredictionRows)
        {
          'matchId': row['match_id'],
          'homeScore': row['home_score'],
          'awayScore': row['away_score'],
          'salt': row['salt'],
          'commit': row['commit_hash'],
          'createdAt': row['created_at'],
        },
    ];
    final mergedPredictions =
        mergePredictions(predictions, normalizedRemotePredictions);
    // Setiap baris kini membawa skor dan `salt`, jadi tidak ada lagi cabang
    // commit-only: semua baris lewat upsert biasa (merge) supaya `home_score`,
    // `away_score`, dan `salt` ikut tersimpan dan bisa memulihkan prediksi yang
    // belum ter-reveal setelah logout/reinstall. Baris cloud privat milik
    // pemilik (RLS), sehingga menulis ketiganya aman.
    final predictionRows = [
      for (final prediction in predictionsToSync(mergedPredictions, chain))
        <String, dynamic>{
          'user_id': userId,
          'match_id': prediction['matchId'],
          'home_score': prediction['homeScore'],
          'away_score': prediction['awayScore'],
          'salt': prediction['salt'],
          'commit_hash': prediction['commit'],
          'created_at': prediction['createdAt'],
        },
    ];
    if (predictionRows.isNotEmpty) {
      await client.from('score_predictions').upsert(
            predictionRows,
            onConflict: 'user_id,match_id',
          );
    }

    final localBlocks = chain.map(Block.fromJson).toList();
    if (!Blockchain.isValid(localBlocks)) {
      throw SyncException('Riwayat lokal tidak cocok dan tidak dikirim.');
    }
    final remoteChainRows = await _selectAll(
      client,
      'passport_chain_blocks',
      userId,
      orderBy: 'idx',
    );
    // Baris cloud dipetakan ke bentuk JSON Block yang sama seperti [Block.toJson]
    // supaya bisa di-parse ulang oleh `Block.fromJson` di sisi pemanggil.
    // `sortBlockRowsByIndex` menormalkan urutan `idx` menaik, sebab urutan
    // bawaan PostgREST menurun dan membuat rantai valid tampak tidak valid.
    final remoteChain = [
      for (final row in sortBlockRowsByIndex(remoteChainRows))
        blockRowToJson(row),
    ];
    final remoteBlocks = SyncRepository.parseChain(remoteChain);

    final ChainOutcome outcome;
    try {
      outcome = reconcileChain(localBlocks, remoteBlocks);
    } on StateError catch (e) {
      throw SyncException(e.message);
    }

    // Hanya kirim blok baru saat lokal yang mendahului cloud. Cloud bersifat
    // append-only, jadi `inSync` dan `adoptRemote` tidak menulis apa pun.
    final rowsToPush = <Map<String, dynamic>>[];
    if (outcome == ChainOutcome.pushLocal) {
      var highestRemoteIdx = -1;
      for (final block in remoteBlocks) {
        if (block.index > highestRemoteIdx) highestRemoteIdx = block.index;
      }
      for (final block in localBlocks) {
        if (block.index > highestRemoteIdx) {
          rowsToPush.add({
            'user_id': userId,
            'idx': block.index,
            'timestamp': block.timestamp,
            'type': block.type,
            'data': block.data,
            'owner': block.owner,
            'prev_hash': block.prevHash,
            'nonce': block.nonce,
            'hash': block.hash,
          });
        }
      }
      if (rowsToPush.isNotEmpty) {
        await client.from('passport_chain_blocks').upsert(
          rowsToPush,
          onConflict: 'user_id,idx',
          ignoreDuplicates: true,
        );
      }
    }

    return SyncResult(
      pushedExpenses: mergedExpenses.length,
      pushedChain: rowsToPush.length,
      pushedPredictions: predictionRows.length,
      mergedExpenses: mergedExpenses.length,
      mergedPredictions: mergedPredictions.length,
      expenses: mergedExpenses,
      predictions: mergedPredictions,
      remoteChain: remoteChain,
      chainOutcome: outcome,
    );
  }

  Future<List<Map<String, dynamic>>> _selectAll(
    supa.SupabaseClient client,
    String table,
    String userId, {
    String? orderBy,
  }) async {
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      dynamic query = client.from(table).select().eq('user_id', userId);
      // ascending: true karena `order()` bawaan PostgREST menurun; rantai
      // harus dibaca idx menaik agar sesuai dengan urutan sebenarnya.
      if (orderBy != null) query = query.order(orderBy, ascending: true);
      final page = await query.range(start, start + pageSize - 1);
      rows.addAll((page as List).cast<Map<String, dynamic>>());
      if (page.length < pageSize) return rows;
      start += pageSize;
    }
  }

  /// Jalankan request dan ubah kegagalan jadi [SyncException] yang informatif
  /// (S3). 401 selalu ditandai supaya pemanggil bisa mengakhiri sesi.
  Future<Map<String, dynamic>> _guard(
      Future<Response<dynamic>> Function() request) async {
    try {
      final res = await request();
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        // Dio biasanya sudah melempar DioException untuk 4xx/5xx. Jalur ini
        // untuk validateStatus yang longgar, jadi perlakukan sama: 401 tetap
        // berarti sesi tidak berlaku.
        throw _fromStatus(code, _errorField(res.data));
      }
      final data = res.data;
      if (data is! Map) {
        throw SyncException('Respons server tidak dikenali');
      }
      return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      throw _fromStatus(
        e.response?.statusCode,
        _errorField(e.response?.data),
        fallback: _describe(e, _errorField(e.response?.data)),
      );
    }
  }

  /// [SyncException] dari kode status, dengan 401 ditandai `unauthorized`.
  static SyncException _fromStatus(
    int? code,
    String? serverMessage, {
    String? fallback,
  }) {
    if (code == 401) {
      return SyncException(
        serverMessage ?? 'Sesi tidak berlaku lagi. Masuk ulang.',
        unauthorized: true,
      );
    }
    return SyncException(
      fallback ??
          serverMessage ??
          'Server menolak pencadangan${code == null ? '' : ' ($code)'}',
    );
  }

  /// Ambil field `error` dari body server, kalau ada dan tidak kosong.
  static String? _errorField(Object? data) {
    if (data is Map) {
      final message = data['error']?.toString().trim() ?? '';
      if (message.isNotEmpty) return message;
    }
    return null;
  }

  static String _describe(DioException e, String? serverMessage) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server tidak terjangkau (waktu habis).';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi ke server. Cek internetmu.';
      case DioExceptionType.badCertificate:
        return 'Sertifikat server tidak valid.';
      case DioExceptionType.cancel:
        return 'Pencadangan dibatalkan.';
      case DioExceptionType.badResponse:
        return serverMessage ??
            'Server menolak pencadangan (${e.response?.statusCode}).';
      case DioExceptionType.unknown:
        return serverMessage ??
            'Pencadangan gagal: ${e.message ?? 'tidak diketahui'}';
      default:
        return serverMessage ?? 'Pencadangan gagal';
    }
  }

  /// Daftar dari server. Bentuk yang tidak terduga diperlakukan sebagai kosong
  /// supaya satu field rusak tidak menggagalkan seluruh sinkronisasi.
  static List<Map<String, dynamic>> _listOfMaps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Jumlah item yang diterima server, aman kalau fieldnya bukan angka.
  static int _countOf(Object? raw) => raw is num ? raw.toInt() : 0;

  /// Ubah JSON rantai dari server menjadi [Block], skipping yang rusak.
  static List<Block> parseChain(List<Map<String, dynamic>> raw) {
    final out = <Block>[];
    for (final j in raw) {
      try {
        out.add(Block.fromJson(j));
      } catch (_) {
        // Satu blok rusak tidak boleh menggagalkan seluruh rantai.
      }
    }
    return out;
  }
}

final syncRepositoryProvider = Provider((ref) =>
    SyncRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider)));
