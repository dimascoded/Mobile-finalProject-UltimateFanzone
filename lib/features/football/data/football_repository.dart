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

enum DataSource { live, cache, sample }

class FootballResult<T> {
  const FootballResult(this.data, this.source, this.fetchedAt);
  final T data;
  final DataSource source;
  final DateTime? fetchedAt;

  FootballResult<R> map<R>(R Function(T) f) =>
      FootballResult(f(data), source, fetchedAt);
}

/// Klien football-data.org (tier gratis: 10 req/menit, skor tertunda).
/// Strategi hemat kuota: cache Hive 15 menit; saat gagal pakai cache lama.
class FootballRepository {
  FootballRepository(this._dio);
  final Dio _dio;

  static const _ttl = Duration(minutes: 15);

  /// TTL pendek saat ada laga yang baru saja kickoff tapi belum FINISHED, supaya
  /// skor tidak basi selama jendela pertandingan.
  static const _recentLiveTtl = Duration(minutes: 3);

  /// Seberapa lama setelah kickoff sebuah laga dianggap "baru mulai".
  static const _recentLiveWindow = Duration(hours: 4);
  static const _keys = ['fd_matches', 'fd_standings', 'fd_scorers'];

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
  Future<void> expire() async {
    for (final k in _keys) {
      await HiveService.cache.delete('${k}_at');
    }
  }

  /// True bila cache matches memuat laga dengan kickoff dalam 4 jam terakhir
  /// yang belum FINISHED (skornya masih mungkin berubah).
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

final footballRepositoryProvider =
    Provider((ref) => FootballRepository(ref.watch(dioProvider)));

// ---- Klub & tim favorit ----
class ClubRepository {
  ClubRepository([
    IdentityStore? identityStore,
    String? Function()? currentUserId,
  ])  : _auth = null,
        _identityStore = identityStore ?? HiveIdentityStore(),
        _currentUserId = currentUserId ?? _noCurrentUser;

  ClubRepository.forAuth(AuthRepository auth)
      : _auth = auth,
        _identityStore = auth.identityStore,
        _currentUserId = _currentUserIdFor(auth);

  static String? Function() _currentUserIdFor(AuthRepository auth) =>
      () => auth.currentUserId;

  final AuthRepository? _auth;
  final IdentityStore _identityStore;
  final String? Function() _currentUserId;

  static String? _noCurrentUser() => null;

  String? get currentUserId => _currentUserId();

  Future<List<PlClub>> load() async {
    final raw = await rootBundle.loadString('assets/data/pl_clubs.json');
    return (jsonDecode(raw) as List)
        .map((e) => PlClub.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

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
