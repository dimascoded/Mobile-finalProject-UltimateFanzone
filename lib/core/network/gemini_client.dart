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
  GeminiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;

  static final _modelPattern = RegExp(r'^[A-Za-z0-9._-]+$');
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Kirim [prompt] ke model pertama di [models] yang bisa dipakai.
  ///
  /// Berpindah ke model berikutnya HANYA saat respons 404. Galat lain langsung
  /// dipetakan ke [GeminiException] dan dihentikan.
  Future<GeminiResult> generate({
    required String apiKey,
    required String prompt,
    required List<String> models,
  }) async {
    GeminiException? lastNotFound;
    for (final model in models) {
      if (!_modelPattern.hasMatch(model)) {
        throw GeminiException('Nama model AI tidak valid: $model');
      }
      try {
        final res = await _dio.post(
          '$_baseUrl/$model:generateContent',
          data: {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
          },
          options: Options(headers: {'x-goog-api-key': apiKey}),
        );
        final text = parseGeminiText(res.data);
        if (text == null) {
          throw GeminiException('Respons AI kosong',
              statusCode: res.statusCode);
        }
        return GeminiResult(text: text, model: model);
      } on DioException catch (e) {
        final failure = geminiFailure(
          statusCode: e.response?.statusCode,
          type: e.type,
        );
        if (failure.statusCode == 404) {
          lastNotFound = failure;
          continue;
        }
        throw failure;
      }
    }
    throw lastNotFound ??
        GeminiException('Model tidak tersedia', modelUnavailable: true);
  }
}
