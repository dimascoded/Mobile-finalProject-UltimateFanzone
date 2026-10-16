import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// Galat dari panggilan Gemini. [message] selalu dalam Bahasa Indonesia dan
/// siap ditampilkan ke pengguna.
class GeminiException implements Exception {
  GeminiException(
    this.message, {
    this.statusCode,
    this.modelUnavailable = false,
  });

  final String message;
  final int? statusCode;

  /// True bila model yang diminta tidak ditemukan (HTTP 404), sehingga
  /// pemanggil boleh mencoba model lain.
  final bool modelUnavailable;

  @override
  String toString() => message;
}

/// Hasil teks dari Gemini, beserta model yang benar-benar berhasil dipakai.
class GeminiResult {
  const GeminiResult({required this.text, required this.model});

  final String text;
  final String model;
}

/// Satu giliran percakapan untuk [GeminiClient.chat].
///
/// [role] harus tepat 'user' atau 'model' sesuai skema Gemini.
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final String role;
  final String text;
}

/// Urutan model yang akan dicoba: [configured], lalu [remembered], lalu
/// [fallbacks]. Duplikat dan string kosong dibuang.
List<String> modelCandidates({
  required String configured,
  String? remembered,
  required List<String> fallbacks,
}) {
  final out = <String>[];
  void add(String? raw) {
    if (raw == null) return;
    final model = raw.trim();
    if (model.isEmpty) return;
    if (!out.contains(model)) out.add(model);
  }

  add(configured);
  add(remembered);
  for (final fallback in fallbacks) {
    add(fallback);
  }
  return out;
}

/// Petakan status/tipe galat Dio ke [GeminiException] berbahasa Indonesia.
GeminiException geminiFailure({
  int? statusCode,
  DioExceptionType? type,
  String? detail,
}) {
  if (type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout) {
    return GeminiException(
      'Permintaan ke AI melewati batas waktu',
      statusCode: statusCode,
    );
  }
  if (type == DioExceptionType.connectionError ||
      type == DioExceptionType.badCertificate) {
    return GeminiException(
      'Tidak ada koneksi internet. Periksa jaringan lalu coba lagi.',
      statusCode: statusCode,
    );
  }
  if (statusCode == 404) {
    return GeminiException(
      'Model tidak tersedia',
      statusCode: statusCode,
      modelUnavailable: true,
    );
  }
  if (statusCode == 401 || statusCode == 403) {
    return GeminiException(
      'API key AI tidak valid atau dibatasi. Periksa kembali kunci akses.',
      statusCode: statusCode,
    );
  }
  if (statusCode == 429) {
    return GeminiException(
      'Kuota atau batas permintaan AI tercapai. Coba lagi nanti.',
      statusCode: statusCode,
    );
  }
  if (statusCode != null && statusCode >= 500) {
    return GeminiException(
      'Server AI sedang sibuk. Coba lagi secara berkala.',
      statusCode: statusCode,
    );
  }
  final suffix = (detail == null || detail.isEmpty) ? '' : ' ($detail)';
  return GeminiException(
    'Permintaan AI gagal$suffix',
    statusCode: statusCode,
  );
}

/// Ambil teks jawaban dari body `generateContent`.
///
/// Hanya `candidates[0].content.parts` yang dibaca, bagian bertanda
/// `thought == true` diabaikan, lalu potongan teks digabung. Mengembalikan
/// null bila tidak ada teks yang bisa dipakai.
String? parseGeminiText(Object? body) {
  if (body is! Map) return null;
  final candidates = body['candidates'];
  if (candidates is! List || candidates.isEmpty) return null;
  final first = candidates.first;
  if (first is! Map) return null;
  final content = first['content'];
  if (content is! Map) return null;
  final parts = content['parts'];
  if (parts is! List) return null;

  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is! Map) continue;
    if (part['thought'] == true) continue;
    final text = part['text'];
    if (text is String) buffer.write(text);
  }
  final out = buffer.toString().trim();
  return out.isEmpty ? null : out;
}

/// Klien REST kecil ke Gemini. Memakai instance [Dio] sendiri tanpa logging
/// interceptor supaya API key tidak pernah tercatat di log.
class GeminiClient {
  GeminiClient({Dio? dio, Future<void> Function(Duration)? sleep})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _sleep = sleep ?? ((duration) => Future<void>.delayed(duration));

  final Dio _dio;

  /// Dapat ditukar pada pengujian supaya backoff tidak benar-benar menunggu.
  final Future<void> Function(Duration) _sleep;

  static final _modelPattern = RegExp(r'^[A-Za-z0-9._-]+$');
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Jeda backoff tanpa header `Retry-After`: sekitar 1 s lalu 2 s, ditambah
  /// jitter acak sampai 300 ms supaya banyak klien tidak menyerbu bersamaan.
  static const _backoffSeconds = <int>[1, 2];

  /// Batas tunggu bila server mengirim header `Retry-After`.
  static const _maxRetryAfter = Duration(seconds: 8);

  /// Batas total satu panggilan [generate] atau [chat].
  static const _overallDeadline = Duration(seconds: 45);

  /// Retry maksimum per model di samping percobaan pertama (total 3).
  static const _maxRetries = 2;

  final Random _random = Random();

  /// Kirim [prompt] ke model pertama di [models] yang bisa dipakai.
  ///
  /// Galat sementara (429, 5xx, timeout, koneksi) diulang pada model yang sama
  /// sampai [_maxRetries] kali, lalu berpindah ke model berikutnya. Respons 404
  /// langsung berpindah model. 400, 401, dan 403 tidak diulang dan tidak
  /// berpindah model.
  Future<GeminiResult> generate({
    required String apiKey,
    required String prompt,
    required List<String> models,
  }) {
    return _send(
      apiKey: apiKey,
      models: models,
      body: {
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      },
    );
  }

  /// Percakapan multi-giliran. [turns] harus diawali dan diakhiri oleh giliran
  /// 'user' dan tidak boleh kosong.
  Future<GeminiResult> chat({
    required String apiKey,
    required String systemInstruction,
    required List<ChatTurn> turns,
    required List<String> models,
  }) async {
    if (turns.isEmpty) {
      throw GeminiException('Riwayat percakapan belum ada');
    }
    if (turns.first.role != 'user') {
      throw GeminiException('Pesan pertama harus berasal dari pengguna');
    }
    if (turns.last.role != 'user') {
      throw GeminiException('Pesan terakhir harus berasal dari pengguna');
    }
    return _send(
      apiKey: apiKey,
      models: models,
      body: {
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
        'contents': [
          for (final turn in turns)
            {
              'role': turn.role,
              'parts': [
                {'text': turn.text},
              ],
            },
        ],
      },
    );
  }

  /// Jalur bersama [generate] dan [chat]: bangun permintaan [body], terapkan
  /// deadline, retry per model, perpindahan model, parsing, dan pemetaan galat.
  Future<GeminiResult> _send({
    required String apiKey,
    required List<String> models,
    required Map<String, Object?> body,
  }) async {
    final clock = Stopwatch()..start();
    GeminiException? lastFailure;
    for (final model in models) {
      if (!_modelPattern.hasMatch(model)) {
        throw GeminiException('Nama model AI tidak valid: $model');
      }
      var retries = 0;
      while (true) {
        final remaining = _overallDeadline - clock.elapsed;
        if (remaining <= Duration.zero) {
          throw lastFailure ??
              geminiFailure(type: DioExceptionType.receiveTimeout);
        }
        try {
          final res = await _dio
              .post(
                '$_baseUrl/$model:generateContent',
                data: body,
                options: Options(headers: {'x-goog-api-key': apiKey}),
              )
              .timeout(remaining);
          final text = parseGeminiText(res.data);
          if (text == null) {
            throw GeminiException('Respons AI kosong',
                statusCode: res.statusCode);
          }
          return GeminiResult(text: text, model: model);
        } on TimeoutException {
          throw lastFailure ??
              geminiFailure(type: DioExceptionType.receiveTimeout);
        } on DioException catch (e) {
          final failure = geminiFailure(
            statusCode: e.response?.statusCode,
            type: e.type,
          );
          lastFailure = failure;
          if (failure.modelUnavailable) {
            break;
          }
          if (!_isRetryable(e)) {
            throw failure;
          }
          if (retries >= _maxRetries) {
            break;
          }
          final delay = _retryDelay(retries, e.response?.headers);
          if (clock.elapsed + delay >= _overallDeadline) {
            throw failure;
          }
          await _sleep(delay);
          retries++;
        }
      }
    }
    throw lastFailure ??
        GeminiException('Model tidak tersedia', modelUnavailable: true);
  }

  /// True bila galat [e] layak diulang pada model yang sama.
  static bool _isRetryable(DioException e) {
    final status = e.response?.statusCode;
    if (status == 429 ||
        status == 500 ||
        status == 502 ||
        status == 503 ||
        status == 504) {
      return true;
    }
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.badCertificate;
  }

  /// Jeda sebelum percobaan ke-[retries]. Pakai `Retry-After` (detik) bila ada,
  /// dibatasi [_maxRetryAfter]; kalau tidak, backoff + jitter.
  Duration _retryDelay(int retries, Headers? headers) {
    final retryAfter = _parseRetryAfter(headers?.value('retry-after'));
    if (retryAfter != null) {
      return retryAfter > _maxRetryAfter ? _maxRetryAfter : retryAfter;
    }
    final seconds = _backoffSeconds[retries < _backoffSeconds.length
        ? retries
        : _backoffSeconds.length - 1];
    return Duration(seconds: seconds, milliseconds: _random.nextInt(300));
  }

  /// Parse header `Retry-After` sebagai detik. Format tanggal HTTP diabaikan.
  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }
}
