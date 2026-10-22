import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/identity_store.dart';
import 'models.dart';
import 'sample_data.dart';

/// Asal data yang dipakai pemanggil, supaya UI bisa menandainya.
///
/// `live` = respons baru dari football-data.org, `cache` = salinan Hive yang
/// masih dipakai, `sample` = data contoh (lihat [SampleData]).
enum DataSource { live, cache, sample }

/// Hasil pemuatan data: isi datanya, asalnya, dan kapan diambil.
///
/// [fetchedAt] null untuk data contoh; untuk data cache nilainya adalah
/// waktu request yang menghasilkan cache itu, bukan waktu cache dibaca.
class FootballResult<T> {
  /// Membungkus data beserta asal dan waktu pengambilan.
  const FootballResult(this.data, this.source, this.fetchedAt);

  /// Data hasil parse (list pertandingan, klasemen, atau pencetak gol).
  final T data;

  /// Asal data: live, cache, atau sample.
  final DataSource source;

  /// Waktu data diambil; null untuk data contoh.
  final DateTime? fetchedAt;

  /// Ubah tipe data tanpa kehilangan asal dan waktu pengambilan.
  FootballResult<R> map<R>(R Function(T) f) =>
      FootballResult(f(data), source, fetchedAt);
}

/// Klien football-data.org (tier gratis: 10 req/menit, skor tertunda).
///
/// Strategi hemat kuota: cache Hive 15 menit; saat gagal pakai cache lama.
///
/// Alur tiap pemanggilan: baca cache Hive `app_cache` pada kunci
/// `fd_matches` / `fd_standings` / `fd_scorers` (body JSON mentah) beserta
/// cap waktu `<kunci>_at` (milidetik epoch); kalau masih segar dalam TTL,
/// kembalikan dari cache tanpa menyentuh jaringan. Kalau perlu request baru,
/// memanggil `https://api.football-data.org/v4/...` dengan header
/// `X-Auth-Token`. Bila gagal, cache lama (kalau ada) dikembalikan;
/// tanpa cache, galat dilempar dengan pesan Bahasa Indonesia.
class FootballRepository {
  /// Membuat repository dengan klien HTTP (lihat `dioProvider`).
  FootballRepository(this._dio);

  /// Klien HTTP untuk memanggil football-data.org.
  final Dio _dio;

  /// TTL cache normal: 15 menit (cukup hemat kuota tier gratis).
  static const _ttl = Duration(minutes: 15);

  /// TTL pendek saat ada laga yang baru saja kickoff tapi belum FINISHED, supaya
  /// skor tidak basi selama jendela pertandingan.
  static const _recentLiveTtl = Duration(minutes: 3);

  /// Seberapa lama setelah kickoff sebuah laga dianggap "baru mulai".
  static const _recentLiveWindow = Duration(hours: 4);

  /// Kunci cache Hive (box `app_cache`) + kunci cap waktunya (`<kunci>_at`).
  static const _keys = ['fd_matches', 'fd_standings', 'fd_scorers'];

  /// Jadwal pertandingan Premier League (`/competitions/PL/matches`).
  ///
  /// Di-cache pada kunci Hive `fd_matches` (body JSON mentah).
  Future<FootballResult<List<FootballMatch>>> matches() => _load(
        key: 'fd_matches',
        path: '/competitions/PL/matches',
        parse: (b) => ((b['matches'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FootballMatch.tryParse(Map<String, dynamic>.from(e)))
            .whereType<FootballMatch>()
            .toList(),
        sample: SampleData.matches,
      );

  /// Klasemen Premier League (`/competitions/PL/standings`).
  ///
  /// Hanya tabel bertipe `TOTAL` yang dipakai. Di-cache pada kunci Hive
  /// `fd_standings`.
  Future<FootballResult<List<StandingRow>>> standings() => _load(
        key: 'fd_standings',
        path: '/competitions/PL/standings',
        parse: (b) {
          final all =
              ((b['standings'] as List?) ?? const []).whereType<Map>().toList();
          Map? total;
          for (final s in all) {
            if (s['type'] == 'TOTAL') {
              total = s;
              break;
            }
          }
          total ??= all.isNotEmpty ? all.first : null;
          return ((total?['table'] as List?) ?? const [])
              .whereType<Map>()
              .map((r) => StandingRow.tryParse(Map<String, dynamic>.from(r)))
              .whereType<StandingRow>()
              .toList();
        },
        sample: SampleData.standings,
      );

  /// Pencetak gol teratas (`/competitions/PL/scorers`).
  ///
  /// Di-cache pada kunci Hive `fd_scorers`.
  Future<FootballResult<List<ScorerRow>>> scorers() => _load(
        key: 'fd_scorers',
        path: '/competitions/PL/scorers',
        parse: (b) => ((b['scorers'] as List?) ?? const [])
            .whereType<Map>()
            .map((r) => ScorerRow.tryParse(Map<String, dynamic>.from(r)))
            .whereType<ScorerRow>()
            .toList(),
        sample: SampleData.scorers,
      );

  /// Tandai cache kedaluwarsa agar panggilan berikutnya mengambil data baru.
  ///
  /// Hanya cap waktu (`fd_matches_at`, `fd_standings_at`, `fd_scorers_at`)
  /// yang dihapus; isi cache tidak dihapus, jadi permintaan berikutnya tetap
  /// bisa memakai cache lama bila jaringan gagal.
  Future<void> expire() async {
    for (final k in _keys) {
      await HiveService.cache.delete('${k}_at');
    }
  }

  /// True bila cache matches memuat laga dengan kickoff dalam 4 jam terakhir
  /// yang belum FINISHED (skornya masih mungkin berubah).
  ///
  /// Membaca body JSON mentah pada kunci Hive `fd_matches`. Cache yang rusak
  /// dianggap "tidak ada" (false), lalu [_load] menangani lewat jalur biasa.
  static bool _hasRecentlyStartedMatch(String? raw) {
    if (raw == null) return false;
    try {
      final body = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final list = (body['matches'] as List?) ?? const [];
      final now = DateTime.now().toUtc();
      for (final e in list) {
        final m = FootballMatch.tryParse(Map<String, dynamic>.from(e as Map));
        if (m == null || m.isFinished) continue;
        final elapsed = now.difference(m.kickoffUtc);
        if (elapsed >= Duration.zero && elapsed <= _recentLiveWindow) {
          return true;
        }
      }
    } catch (_) {
      // Cache rusak: biarkan _load menangani lewat jalur biasa.
    }
    return false;
  }

  /// Alur pemuatan generik: cache → jaringan → fallback.
  ///
  /// - Cache: kunci [key] (body JSON mentah) dan `<key>_at` (milidetik
  ///   epoch) di Hive box `app_cache`. TTL 15 menit, atau 3 menit untuk
  ///   `fd_matches` saat ada laga yang baru saja dimulai.
  /// - Jaringan: hanya dijalankan bila `FOOTBALL_API_KEY` terisi
  ///   ([AppConfig.footballApiKey]). Tanpa key, aplikasi memakai cache lama
  ///   bila ada, jika tidak data contoh [SampleData] dengan
  ///   [DataSource.sample].
  /// - Fallback: saat request gagal, cache lama dikembalikan; tanpa cache,
  ///   galat dilempar dengan pesan Bahasa Indonesia (429 = kuota habis,
  ///   401/403 = key ditolak, selain itu = masalah koneksi).
  ///
  /// [parse] menerima body JSON mentah hasil respons dan mengembalikan
  /// data yang sudah ditolak yang rusak (item yang gagal di-parse dilewati).
  Future<FootballResult<T>> _load<T>({
    required String key,
    required String path,
    required T Function(Map<String, dynamic>) parse,
    required T Function() sample,
  }) async {
    final raw = HiveService.cache.get(key);
    final atMs = int.tryParse(HiveService.cache.get('${key}_at') ?? '');
    final fetchedAt =
        atMs == null ? null : DateTime.fromMillisecondsSinceEpoch(atMs);
    final ttl = key == 'fd_matches' && _hasRecentlyStartedMatch(raw)
        ? _recentLiveTtl
        : _ttl;
    final fresh =
        fetchedAt != null && DateTime.now().difference(fetchedAt) < ttl;

    FootballResult<T>? fromCache() => raw == null
        ? null
        : FootballResult(
            parse(Map<String, dynamic>.from(jsonDecode(raw) as Map)),
            DataSource.cache,
            fetchedAt,
          );

    if (fresh) {
      final c = fromCache();
      if (c != null) return c;
    }

    // Tanpa API key: pakai cache lama jika ada, selain itu data contoh.
    if (AppConfig.footballApiKey.isEmpty) {
      return fromCache() ?? FootballResult(sample(), DataSource.sample, null);
    }

    try {
      final res = await _dio.get(
        '${AppConfig.footballBaseUrl}$path',
        options: Options(headers: {'X-Auth-Token': AppConfig.footballApiKey}),
      );
      final body = Map<String, dynamic>.from(res.data as Map);
      final now = DateTime.now();
      await HiveService.cache.put(key, jsonEncode(body));
      await HiveService.cache
          .put('${key}_at', now.millisecondsSinceEpoch.toString());
      return FootballResult(parse(body), DataSource.live, now);
    } on DioException catch (e) {
      final stale = fromCache();
      if (stale != null) {
        return stale; // offline / limit: tampilkan data terakhir
      }
      final code = e.response?.statusCode;
      if (code == 429) {
        throw Exception(
            'Batas permintaan API (10/menit) tercapai. Coba lagi sebentar.');
      }
      if (code == 401 || code == 403) {
        throw Exception(
            'API key ditolak atau kompetisi tidak tersedia di tier gratis.');
      }
      throw Exception(
          'Gagal memuat data pertandingan. Periksa koneksi internet.');
    }
  }
}

/// Repository tunggal untuk football-data.org (dengan Dio yang sama).
final footballRepositoryProvider =
    Provider((ref) => FootballRepository(ref.watch(dioProvider)));

// ---- Klub & tim favorit ----

/// Sumber data klub Premier League dan tim favorit pengguna.
///
/// Daftar klub dibaca dari aset `assets/data/pl_clubs.json` (lokal, tanpa
/// jaringan). Tim favorit disimpan di Hive box `app_cache` pada kunci
/// `favorite_team_<userId>` dan, bila tersedia, disalin dari metadata
/// Supabase (`favorite_team`).
class ClubRepository {
  /// Repository mandiri tanpa [AuthRepository]: simpan langsung ke
  /// [identityStore] memakai kunci ber-sufiks user id.
  ClubRepository([
    IdentityStore? identityStore,
    String? Function()? currentUserId,
  ])  : _auth = null,
        _identityStore = identityStore ?? HiveIdentityStore(),
        _currentUserId = currentUserId ?? _noCurrentUser;

  /// Repository yang mendelegasikan penyimpanan ke [AuthRepository] sehingga
  /// migrasi nilai legacy dan sinkronisasi cloud ikut bekerja.
  ClubRepository.forAuth(AuthRepository auth)
      : _auth = auth,
        _identityStore = auth.identityStore,
        _currentUserId = _currentUserIdFor(auth);

  /// Pembaca user id dari [AuthRepository] yang aktif.
  static String? Function() _currentUserIdFor(AuthRepository auth) =>
      () => auth.currentUserId;

  /// Auth aktif; null bila repository dipakai tanpa [AuthRepository].
  final AuthRepository? _auth;

  /// Penyimpanan lokal nilai (Hive box `app_cache`).
  final IdentityStore _identityStore;

  /// Sumber user id untuk menyufikskan kunci Hive.
  final String? Function() _currentUserId;

  /// Pengguna dianggap belum masuk.
  static String? _noCurrentUser() => null;

  /// Id user aktif, atau null bila belum masuk.
  String? get currentUserId => _currentUserId();

  /// Muat daftar klub Premier League dari aset `assets/data/pl_clubs.json`.
  ///
  /// Mengembalikan objek [PlClub] lengkap dengan stadion, koordinat, warna,
  /// dan alias nama untuk pencocokan tim.
  Future<List<PlClub>> load() async {
    final raw = await rootBundle.loadString('assets/data/pl_clubs.json');
    return (jsonDecode(raw) as List)
        .map((e) => PlClub.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Kode klub tim favorit, atau null bila belum ada.
  ///
  /// Urutan sumber: nilai lokal di Hive (`favorite_team_<userId>`, termasuk
  /// nilai legacy global yang diadopsi), lalu metadata cloud
  /// (`favorite_team`). Nilai dari cloud ikut ditulis balik ke Hive supaya
  /// dibaca berikutnya tanpa jaringan.
  String? favoriteKey() {
    final userId = currentUserId;
    if (userId == null) return null;
    final auth = _auth;
    final local = auth != null
        ? auth.readUserScopedValue('favorite_team')
        : _identityStore.get(AuthRepository.favoriteTeamKey(userId));
    if (local != null) return local;
    final cloud = auth?.cloudFavoriteTeam();
    if (cloud != null && auth != null) {
      unawaited(auth.writeUserScopedValue('favorite_team', cloud));
    }
    return cloud;
  }

  /// Simpan tim favorit ke Hive saja (tanpa menyentuh cloud).
  ///
  /// Diabaikan bila belum ada user id.
  Future<void> saveFavorite(String value) async {
    final userId = currentUserId;
    if (userId == null) return;
    final auth = _auth;
    if (auth != null) {
      await auth.writeUserScopedValue('favorite_team', value);
    } else {
      await _identityStore.put(AuthRepository.favoriteTeamKey(userId), value);
    }
  }

  /// Simpan tim favorit ke Hive lalu ke metadata cloud.
  ///
  /// Mengembalikan true bila nilai tersimpan di cloud (atau tidak ada cloud
  /// yang bisa dipakai); false bila penulisan cloud gagal, sehingga UI bisa
  /// memberi tahu bahwa nilainya belum tersinkron.
  Future<bool> saveFavoriteWithCloudStatus(String value) async {
    if (currentUserId == null) return false;
    await saveFavorite(value);
    final auth = _auth;
    return auth == null
        ? true
        : await auth.saveProfilePrefs(favoriteTeam: value);
  }
}

final clubRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return ClubRepository.forAuth(auth);
});
