import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../away_day/data/away_day_repository.dart';
import '../../gamification/data/blockchain.dart';
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
    List<AwayDayExpense>? expenses,
    List<Prediction>? predictions,
    List<Map<String, dynamic>>? remoteChain,
    this.adoptedChain = false,
    this.unauthorized = false,
  })  : // S1: kembalikan daftar hasil merge, bukan hanya jumlah, supaya
        // SyncNotifier benar-benar menerapkannya ke Hive.
        expenses = expenses ?? const [],
        predictions = predictions ?? const [],
        remoteChain = remoteChain ?? const [];

  final int pushedExpenses, pushedChain, pushedPredictions;
  final int mergedExpenses, mergedPredictions;

  /// true = tidak ada BACKEND_URL, jadi sinkronisasi disimulasikan.
  final bool mock;

  /// Daftar gabungan yang harus ditulis ke Hive.
  final List<AwayDayExpense> expenses;
  final List<Prediction> predictions;

  /// Rantai dari server, untuk diperiksa [Blockchain.canAdoptRemote].
  final List<Map<String, dynamic>> remoteChain;

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
    String baseUrl = AppConfig.backendUrl,
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

  bool get isMock => _baseUrl.isEmpty;

  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    Map<String, dynamic>? feedback,
  }) async {
    if (isMock) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // Kembalikan daftar lokal apa adanya: mode mock tidak boleh menyentuh
      // Hive, jadi `replaceAll` nanti hanya menulis ulang data yang sama.
      return SyncResult(
        pushedExpenses: expenses.length,
        pushedChain: chain.length,
        pushedPredictions: predictions.length,
        mergedExpenses: expenses.length,
        mergedPredictions: predictions.length,
        mock: true,
        expenses: expenses,
        predictions: predictions,
      );
    }

    final token = await _tokenLoader();
    if (token == null || token.isEmpty) {
      throw SyncException('Belum login. Masuk dulu sebelum sinkronisasi.');
    }
    final headers = {'Authorization': 'Bearer $token'};
    final payload = SyncPayload(
      expenses: expenses.map(expenseToJson).toList(),
      chain: chainToJson(chain),
      // S4: sebelum kickoff hanya commit yang boleh keluar. Skor dan salt
      // baru dikirim setelah blok result ada di rantai lokal.
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
          'Server menolak sinkronisasi${code == null ? '' : ' ($code)'}',
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
        return 'Sinkronisasi dibatalkan.';
      case DioExceptionType.badResponse:
        return serverMessage ??
            'Server menolak sinkronisasi (${e.response?.statusCode}).';
      case DioExceptionType.unknown:
        return serverMessage ??
            'Sinkronisasi gagal: ${e.message ?? 'tidak diketahui'}';
      default:
        return serverMessage ?? 'Sinkronisasi gagal';
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
