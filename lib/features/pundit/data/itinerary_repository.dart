import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../trip/data/models.dart';
import 'itinerary_parser.dart';

class ItineraryResult {
  ItineraryResult(this.text, {this.fromCache = false})
      : days = ItineraryParser.parse(text);
  final String text; // teks mentah dari Gemini (disimpan untuk offline)
  final bool fromCache;
  final List<ItineraryDay>? days; // null jika bukan JSON valid -> tampil teks mentah
}

class ItineraryRepository {
  String _key(String countryId) => 'itinerary_$countryId';

  Future<ItineraryResult> generate(Country country, Trip trip) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diset (gunakan --dart-define)');
    }
    final model = GenerativeModel(
      model: AppConfig.geminiModel,
      apiKey: AppConfig.geminiApiKey,
    );
    final place = trip.city.isEmpty
        ? '${country.name} (pilih rute kota yang masuk akal)'
        : '${trip.city}, ${country.name}';
    final prompt = 'Buatkan itinerary perjalanan ${trip.days} hari ke $place. '
        'Balas HANYA dengan JSON array valid tanpa teks lain, format: '
        '[{"day":1,"title":"judul singkat","items":[{"time":"09:00","activity":"kegiatan","cost":0}]}]. '
        'Isi "cost" dengan angka perkiraan biaya dalam ${country.currency} (tanpa simbol). '
        'Gunakan bahasa Indonesia. Sertakan landmark: '
        '${country.landmarks.map((l) => l.name).join(', ')}.';
    final res = await model.generateContent([Content.text(prompt)]);
    final text = res.text;
    if (text == null || text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_key(country.id), text); // untuk mode offline
    return ItineraryResult(text);
  }

  ItineraryResult? cached(String? countryId) {
    if (countryId == null) return null;
    final v = HiveService.cache.get(_key(countryId));
    return v == null ? null : ItineraryResult(v, fromCache: true);
  }
}

final itineraryRepositoryProvider = Provider((ref) => ItineraryRepository());
