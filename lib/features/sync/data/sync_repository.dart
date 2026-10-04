import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../away_day/data/away_day_repository.dart';
import '../../prediction/data/prediction_repository.dart';
import 'sync_models.dart';

/// Hasil satu siklus sinkronisasi.
class SyncResult {
  const SyncResult({
    this.pushedExpenses = 0,
    this.pushedChain = 0,
    this.pushedPredictions = 0,
    this.mergedExpenses = 0,
    this.mergedPredictions = 0,
    this.mock = false,
  });

  final int pushedExpenses, pushedChain, pushedPredictions;
  final int mergedExpenses, mergedPredictions;

  /// true = tidak ada BACKEND_URL, jadi sinkronisasi disimulasikan.
  final bool mock;
}

/// Kirim data lokal ke server, lalu tarik data server untuk digabung.
///
/// Mode offline-first: aplikasi tetap menulis ke Hive lebih dulu, jadi
/// [SyncRepository.sync] gagal (tidak ada internet) tidak menghapus data lokal.
class SyncRepository {
  SyncRepository(this._dio, this._auth);

  final Dio _dio;
  final AuthRepository _auth;

  bool get isMock => AppConfig.backendUrl.isEmpty;

  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    Map<String, dynamic>? feedback,
  }) async {
    if (isMock) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return SyncResult(
        pushedExpenses: expenses.length,
        pushedChain: chain.length,
        pushedPredictions: predictions.length,
        mock: true,
      );
    }

    final token = await _auth.currentToken();
    if (token == null || token.isEmpty) {
      throw Exception('Belum login. Masuk dulu sebelum sinkronisasi.');
    }
    final headers = {'Authorization': 'Bearer $token'};
    final payload = SyncPayload(
      expenses: expenses.map(expenseToJson).toList(),
      chain: chainToJson(chain),
      predictions: predictions.map(predictionToJson).toList(),
      feedback: feedback,
    );

    // 1. Push. Kalau gagal, data lokal tetap utuh karena Hive sudah menyimpannya.
    final res = await _dio.post(
      '${AppConfig.backendUrl}/sync',
      data: payload.toJson(),
      options: Options(headers: headers),
    );
    if (res.statusCode != 200) {
      throw Exception('Server menolak sinkronisasi (${res.statusCode})');
    }
    final body = Map<String, dynamic>.from(res.data as Map);

    // 2. Pull.
    final pullRes = await _dio.get(
      '${AppConfig.backendUrl}/sync',
      options: Options(headers: headers),
    );
    if (pullRes.statusCode != 200) {
      throw Exception('Gagal menarik data (${pullRes.statusCode})');
    }
    final remote = Map<String, dynamic>.from(pullRes.data as Map);

    final remoteExpenses = _listOfMaps(remote['expenses']);
    final remotePredictions = _listOfMaps(remote['predictions']);

    return SyncResult(
      pushedExpenses: (body['expenses'] as num?)?.toInt() ?? 0,
      pushedChain: (body['chain'] as num?)?.toInt() ?? 0,
      pushedPredictions: (body['predictions'] as num?)?.toInt() ?? 0,
      mergedExpenses: mergeExpenses(expenses, remoteExpenses).length,
      mergedPredictions: mergePredictions(predictions, remotePredictions).length,
    );
  }

  static List<Map<String, dynamic>> _listOfMaps(Object? raw) =>
      ((raw as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
}

final syncRepositoryProvider = Provider(
    (ref) => SyncRepository(ref.watch(dioProvider), ref.watch(authRepositoryProvider)));
