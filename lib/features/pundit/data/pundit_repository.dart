import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/network/gemini_client.dart';
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
  PunditRepository({GeminiClient? client}) : _client = client ?? GeminiClient();

  final GeminiClient _client;

  /// Key Hive berisi model Gemini yang terakhir berhasil, supaya request
  /// berikutnya mencoba model itu lebih dulu.
  static const _workingModelKey = 'gemini_model_ok';

  String _key(String clubKey) => 'pundit_$clubKey';

  Future<PunditResult> generate(PlClub club, List<StandingRow> standings,
      List<FootballMatch> last5) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diset (gunakan --dart-define)');
    }
    // UI6: kalau klasemen atau riwayat kosong, prompt tidak boleh berisi
    // "Klasemen: ." yang membuat model mengarang angka. Bagian yang tidak ada
    // diganti kalimat eksplisit, dan model diminta menyatakan keterbatasan.
    String rowText(StandingRow s) =>
        '${s.position}.${s.teamShort} ${s.points}pts';
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
    final remembered = HiveService.cache.get(_workingModelKey);
    final models = modelCandidates(
      configured: AppConfig.geminiModel,
      remembered: remembered,
      fallbacks: AppConfig.geminiFallbackModels,
    );
    final GeminiResult res;
    try {
      res = await _client.generate(
        apiKey: AppConfig.geminiApiKey,
        prompt: prompt,
        models: models,
      );
    } on GeminiException catch (e) {
      throw Exception(e.message);
    }
    final text = res.text;
    if (text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_workingModelKey, res.model);
    await HiveService.cache.put(_key(club.key), text);
    await HiveService.cache
        .put('${_key(club.key)}_at', DateTime.now().toUtc().toIso8601String());
    return PunditResult(text);
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
