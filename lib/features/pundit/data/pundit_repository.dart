import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../football/data/models.dart';

class PunditResult {
  PunditResult(this.text, {this.fromCache = false});
  final String text;
  final bool fromCache;
}

class PunditRepository {
  String _key(String clubKey) => 'pundit_$clubKey';

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
    final res = await model.generateContent([Content.text(prompt)]);
    final text = res.text;
    if (text == null || text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_key(club.key), text);
    return PunditResult(text);
  }

  PunditResult? cached(String? clubKey) {
    if (clubKey == null) return null;
    final v = HiveService.cache.get(_key(clubKey));
    return v == null ? null : PunditResult(v, fromCache: true);
  }
}
final punditRepositoryProvider = Provider((ref) => PunditRepository());