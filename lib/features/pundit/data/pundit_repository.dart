import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/network/gemini_client.dart';
import '../../../core/utils/app_config.dart';
import '../../football/data/models.dart';
import 'pundit_chat.dart';

/// Hasil analisis AI untuk satu klub.
class PunditResult {
  /// Membuat hasil analisis.
  PunditResult(
    this.text, {
    this.fromCache = false,
    this.cachedAt,
    this.warning,
  });

  /// Teks analisis (atau balasan chat) yang ditampilkan ke pengguna.
  final String text;

  /// True bila teks berasal dari cache, bukan request baru.
  final bool fromCache;

  /// Waktu cache dibuat; null untuk hasil request baru.
  final DateTime? cachedAt;

  /// Terisi kalau teks ini bukan hasil request baru, tapi cache lama yang
  /// dipakai setelah request gagal. UI wajib menampilkannya supaya pengguna
  /// tidak mengira analisisnya baru saja dibuat.
  final String? warning;

  /// Salinan dengan [warning] baru (tanpa mengubah teks).
  PunditResult copyWith({String? warning}) => PunditResult(
        text,
        fromCache: fromCache,
        cachedAt: cachedAt,
        warning: warning ?? this.warning,
      );
}

/// Repository analisis & obrolan "Pundit" berbasis Gemini.
///
/// Cache memakai Hive box `app_cache`:
/// - `gemini_model_ok` — model Gemini yang terakhir berhasil (dipakai lebih
///   dulu pada request berikutnya).
/// - `pundit_<clubKey>` — teks analisis terbaru untuk sebuah klub, dan
///   `pundit_<clubKey>_at` — waktu analisis itu dibuat (ISO-8601).
/// - `pundit_chat_<clubKey>` — riwayat chat klub (maks. 30 pesan terakhir).
///
/// Semua kunci diawali `pundit_` (kecuali `gemini_model_ok`), jadi
/// [clearCache] bisa membersihkannya sekaligus saat logout.
class PunditRepository {
  /// Repository dengan [GeminiClient] bawaan.
  PunditRepository({GeminiClient? client}) : _client = client ?? GeminiClient();

  /// Klien Gemini yang dipakai untuk generate dan chat.
  final GeminiClient _client;

  /// Key Hive berisi model Gemini yang terakhir berhasil, supaya request
  /// berikutnya mencoba model itu lebih dulu.
  static const _workingModelKey = 'gemini_model_ok';

  /// Awalan key riwayat chat per klub. Ikut terhapus oleh [clearCache] karena
  /// semuanya diawali 'pundit_'.
  static const _chatKeyPrefix = 'pundit_chat_';

  /// Batas pesan yang disimpan per klub.
  static const _maxChatMessages = 30;

  /// Kunci cache analisis sebuah klub (dan cap waktunya + `_at`).
  String _key(String clubKey) => 'pundit_$clubKey';

  /// Kunci cache riwayat chat sebuah klub.
  String _chatKey(String clubKey) => '$_chatKeyPrefix$clubKey';

  /// Buat analisis singkat untuk [club] dari klasemen dan 5
  /// hasil terakhir.
  ///
  /// Melempar [Exception] dengan pesan Bahasa Indonesia bila
  /// `GEMINI_API_KEY` belum diset atau respons AI kosong. Klasemen kosong
  /// diganti kalimat eksplisit ("Data klasemen belum tersedia") supaya model
  /// tidak mengarang angka; baris klub sendiri selalu ikut yang dikirim.
  ///
  /// Hasil sukses disimpan ke Hive pada `pundit_<clubKey>` (dan
  /// `pundit_<clubKey>_at`), dan model yang berhasil dicatat di
  /// `gemini_model_ok`.
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

  /// Balasan percakapan multi-giliran "Tanya Pundit".
  ///
  /// Memakai kandidat model dan model yang diingat yang sama seperti
  /// [generate], dan menyimpan model yang berhasil.
  ///
  /// [systemInstruction] berisi aturan dan data pengikat hasil
  /// [buildSystemInstruction]; [turns] adalah giliran yang sudah dipangkas
  /// oleh [trimTurns]. Melempar [Exception] berbahasa Indonesia bila
  /// `GEMINI_API_KEY` belum diset atau respons kosong.
  Future<String> chatReply({
    required String systemInstruction,
    required List<ChatTurn> turns,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diset (gunakan --dart-define)');
    }
    final remembered = HiveService.cache.get(_workingModelKey);
    final models = modelCandidates(
      configured: AppConfig.geminiModel,
      remembered: remembered,
      fallbacks: AppConfig.geminiFallbackModels,
    );
    final GeminiResult res;
    try {
      res = await _client.chat(
        apiKey: AppConfig.geminiApiKey,
        systemInstruction: systemInstruction,
        turns: turns,
        models: models,
      );
    } on GeminiException catch (e) {
      throw Exception(e.message);
    }
    final text = res.text;
    if (text.isEmpty) throw Exception('Respons AI kosong');
    await HiveService.cache.put(_workingModelKey, res.model);
    return text;
  }

  /// Muat riwayat chat klub. Data rusak dikembalikan sebagai daftar kosong.
  ///
  /// Sumbernya kunci Hive `pundit_chat_<clubKey>` (box `app_cache`) berisi
  /// JSON array pesan; pesan yang tidak valid dilewati satu per satu.
  List<ChatMessage> loadChat(String clubKey) {
    final raw = HiveService.cache.get(_chatKey(clubKey));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <ChatMessage>[];
      for (final item in decoded) {
        final m = ChatMessage.fromJson(item);
        if (m != null) out.add(m);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Simpan riwayat chat klub, menyisakan [_maxChatMessages] pesan terakhir.
  ///
  /// Menulis ke kunci Hive `pundit_chat_<clubKey>` (box `app_cache`).
  Future<void> saveChat(String clubKey, List<ChatMessage> messages) async {
    final kept = messages.length > _maxChatMessages
        ? messages.sublist(messages.length - _maxChatMessages)
        : messages;
    final encoded = jsonEncode([for (final m in kept) m.toJson()]);
    await HiveService.cache.put(_chatKey(clubKey), encoded);
  }

  /// Ambil analisis yang tersimpan untuk sebuah klub.
  ///
  /// Membaca Hive `pundit_<clubKey>` dan cap waktu `pundit_<clubKey>_at`.
  /// Null kalau belum pernah ada analisis atau clubKey null (belum ada klub
  /// terpilih).
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
  ///
  /// Menghapus semua kunci Hive yang diawali `pundit_` (analisis per klub,
  /// cap waktunya, dan riwayat chat per klub).
  static Future<void> clearCache() async {
    final keys =
        HiveService.cache.keys.where((k) => k.startsWith('pundit_')).toList();
    await HiveService.cache.deleteAll(keys);
  }
}

/// Repository pundit bersama (memakai [GeminiClient] bawaan).
final punditRepositoryProvider = Provider((ref) => PunditRepository());
