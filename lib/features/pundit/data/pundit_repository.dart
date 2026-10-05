import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../football/data/models.dart';

class PunditResult {
  PunditResult(
    this.text, {
    this.fromCache = false,
    this.cachedAt,
    this.warning,
  });
  final String text;
  final bool fromCache;
  final DateTime? cachedAt;

  /// Terisi kalau teks ini bukan hasil request baru, tapi cache lama yang
  /// dipakai setelah request gagal. UI wajib menampilkannya supaya pengguna
  /// tidak mengira analisisnya baru saja dibuat.
  final String? warning;

  PunditResult copyWith({String? warning}) => PunditResult(
        text,
        fromCache: fromCache,
        cachedAt: cachedAt,
        warning: warning ?? this.warning,
      );
}

class PunditRepository {
  String _key(String clubKey) => 'pundit_$clubKey';

  /// Model tidak ditemukan (404 / NOT_FOUND) -> sarankan ganti GEMINI_MODEL.
  static bool isModelMissing(Object error) {
    final s = error.toString();
    return s.contains('404') ||
        s.contains('NOT_FOUND') ||
        s.contains('is not found for API version');
  }

  static String modelMissingMessage() =>
      'Model "${AppConfig.geminiModel}" tidak tersedia. '
      'Perbarui GEMINI_MODEL saat build, contoh: '
      '--dart-define=GEMINI_MODEL=gemini-3.8-flash';

  Future<PunditResult> generate(PlClub club, List<StandingRow> standings,
      List<FootballMatch> last5) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diset (gunakan --dart-define)');
    }
    final model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
    );
    // UI6: kalau klasemen atau riwayat kosong, prompt tidak boleh berisi
    // "Klasemen: ." yang membuat model mengarang angka. Bagian yang tidak ada
    // diganti kalimat eksplisit, dan model diminta menyatakan keterbatasan.
    String rowText(StandingRow s) => '${s.position}.${s.teamShort} ${s.points}pts';
    // Baris klub favorit selalu ikut, walau posisinya di luar enam teratas.
    // Tanpa ini model bisa salah menyebut posisi tim yang jadi dasar analisis.
    final own = standings.where((s) => s.teamShort == club.tla).toList();
    final rows = <String>{
      ...standings.take(6).map(rowText),
      ...own.map(rowText),
    }.toList();
    final standingsText = standings.isEmpty
        ? 'Data klasemen belum tersedia.'
        : 'Klasemen: ${rows.join(', ')}. '
            'Posisi ${club.tla}: '
            '${own.isEmpty ? 'tidak ada di data' : rowText(own.first)}.';
    final resultsText = last5.isEmpty
        ? 'Riwayat 5 laga belum tersedia.'
        : '5 hasil terakhir: ${last5.map((m) => '${m.homeShort} vs ${m.awayShort} (${m.homeScore}-${m.awayScore}, ${m.status})').join('; ')}.';

    final prompt = 'Buat analisis singkat untuk penggemar ${club.name}. '
        '$standingsText $resultsText '
        'Jangan mengarang angka, pemain, atau hasil yang tidak ada di data di atas; '
        'kalau datanya kurang, sebutkan kekurangannya. '
        'Berikan prediksi realistis (bukan rekomendasi betting), kekuatan/lemahnya, dan saran nonton. '
        'Balas dalam bahasa Indonesia, max 200 kata, dalam 3 paragraf.';
    final res = await _generate(model, prompt);
    final text = res.text ?? '';
    if (text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_key(club.key), text);
    await HiveService.cache
        .put('${_key(club.key)}_at', DateTime.now().toUtc().toIso8601String());
    return PunditResult(text);
  }

  static Future<GenerateContentResponse> _generate(
      GenerativeModel model, String prompt) async {
    try {
      return await model.generateContent([Content.text(prompt)]);
    } on GenerativeAIException catch (e) {
      if (isModelMissing(e)) throw Exception(modelMissingMessage());
      throw Exception('Pundit AI gagal: ${e.message}');
    } on Exception catch (e) {
      if (isModelMissing(e)) throw Exception(modelMissingMessage());
      rethrow;
    }
  }

  PunditResult? cached(String? clubKey) {
    if (clubKey == null) return null;
    final v = HiveService.cache.get(_key(clubKey));
    if (v == null) return null;
    final at = HiveService.cache.get('${_key(clubKey)}_at');
    return PunditResult(v,
        fromCache: true, cachedAt: DateTime.tryParse(at ?? ''));
  }

  /// Hapus seluruh cache analisis (dipakai saat logout agar tidak bocor
  /// ke pengguna berikutnya di perangkat yang sama).
  static Future<void> clearCache() async {
    final keys =
        HiveService.cache.keys.where((k) => k.startsWith('pundit_')).toList();
    await HiveService.cache.deleteAll(keys);
  }
}

final punditRepositoryProvider = Provider((ref) => PunditRepository());
