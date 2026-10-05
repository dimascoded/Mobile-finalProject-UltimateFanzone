import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../football/data/models.dart';

class PunditResult {
  PunditResult(this.text, {this.fromCache = false, this.cachedAt});
  final String text;
  final bool fromCache;
  final DateTime? cachedAt;
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

  Future<PunditResult> generate(PlClub club, List<StandingRow> standings, List<FootballMatch> last5) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diset (gunakan --dart-define)');
    }
    final model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
    );
    final last = last5.map((m) => '${m.homeShort} vs ${m.awayShort} (${m.homeScore}-${m.awayScore}, ${m.status})').join('; ');
    final prompt = 'Buat analisis singkat untuk penggemar ${club.name}. '
        'Klasemen top 5 relevan: ${standings.take(6).map((s) => '${s.position}.${s.teamShort} ${s.points}pts').join(', ')}. '
        '5 hasil terakhir: $last. '
        'Berikan prediksi realistis (bukan taruhan), kekuatan/lemahnya, dan saran nonton. '
        'Balas dalam bahasa Indonesia, max 200 kata.';
    final res = await _generate(model, prompt);
    final text = res.text ?? '';
    if (text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_key(club.key), text);
    await HiveService.cache.put(
        '${_key(club.key)}_at', DateTime.now().toUtc().toIso8601String());
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