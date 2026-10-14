import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/football_repository.dart';
import '../data/models.dart';

// ---------- Klub & tim favorit ----------
final clubsProvider = FutureProvider<List<PlClub>>(
    (ref) => ref.watch(clubRepositoryProvider).load());

class FavoriteTeamNotifier extends StateNotifier<String?> {
  FavoriteTeamNotifier(this._repo) : super(_repo.favoriteKey());
  final ClubRepository _repo;

  Future<void> set(String key) async {
    state = key;
    await _repo.saveFavorite(key);
  }
}

final favoriteKeyProvider =
    StateNotifierProvider<FavoriteTeamNotifier, String?>(
        (ref) => FavoriteTeamNotifier(ref.watch(clubRepositoryProvider)));

final favoriteClubProvider = Provider<PlClub?>((ref) {
  final key = ref.watch(favoriteKeyProvider);
  final clubs = ref.watch(clubsProvider).valueOrNull;
  if (key == null || clubs == null) return null;
  for (final c in clubs) {
    if (c.key == key) return c;
  }
  return null;
});

// ---------- Data pertandingan ----------
final matchesProvider = FutureProvider<FootballResult<List<FootballMatch>>>(
    (ref) => ref.watch(footballRepositoryProvider).matches());

final standingsProvider = FutureProvider<FootballResult<List<StandingRow>>>(
    (ref) => ref.watch(footballRepositoryProvider).standings());

final scorersProvider = FutureProvider<FootballResult<List<ScorerRow>>>(
    (ref) => ref.watch(footballRepositoryProvider).scorers());

/// Peta TLA tim -> URL crest, dibangun dari laga terakhir (football-data.org).
///
/// Klub di `pl_clubs.json` tidak menyimpan crest, jadi tampilan berbasis
/// `PlClub` memakai peta ini. Bila kosong (data contoh/offline) pemanggil
/// otomatis jatuh ke badge warna + TLA.
final clubCrestProvider = Provider<Map<String, String>>((ref) {
  final map = <String, String>{};
  final matches =
      ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  for (final m in matches) {
    final home = m.homeCrest;
    if (home != null && home.isNotEmpty && m.homeTla != null) {
      map[m.homeTla!.toUpperCase()] = home;
    }
    final away = m.awayCrest;
    if (away != null && away.isNotEmpty && m.awayTla != null) {
      map[m.awayTla!.toUpperCase()] = away;
    }
  }
  return map;
});

/// Muat ulang paksa (cache dikosongkan lalu provider di-invalidate).
final footballRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(footballRepositoryProvider).expire();
    ref.invalidate(matchesProvider);
    ref.invalidate(standingsProvider);
    ref.invalidate(scorersProvider);
  };
});

// ---------- Filter & pencarian jadwal ----------
enum MatchFilter { upcoming, favorite, finished, all }

final matchFilterProvider =
    StateProvider.autoDispose<MatchFilter>((ref) => MatchFilter.upcoming);
final matchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final filteredMatchesProvider =
    Provider.autoDispose<AsyncValue<FootballResult<List<FootballMatch>>>>(
        (ref) {
  final filter = ref.watch(matchFilterProvider);
  final q = ref.watch(matchQueryProvider).toLowerCase().trim();
  final fav = ref.watch(favoriteClubProvider);

  return ref.watch(matchesProvider).whenData((r) {
    final list = r.data.where((m) {
      if (q.isNotEmpty &&
          !m.homeName.toLowerCase().contains(q) &&
          !m.awayName.toLowerCase().contains(q)) {
        return false;
      }
      switch (filter) {
        case MatchFilter.upcoming:
          return !m.isFinished;
        case MatchFilter.finished:
          return m.isFinished;
        case MatchFilter.favorite:
          return fav != null && m.involves(fav);
        case MatchFilter.all:
          return true;
      }
    }).toList();
    list.sort((a, b) => filter == MatchFilter.finished
        ? b.kickoffUtc.compareTo(a.kickoffUtc)
        : a.kickoffUtc.compareTo(b.kickoffUtc));
    return FootballResult(list, r.source, r.fetchedAt);
  });
});

/// Laga berikutnya milik tim favorit (null jika tidak ada / belum memilih tim).
final nextMatchProvider = Provider<AsyncValue<FootballMatch?>>((ref) {
  final fav = ref.watch(favoriteClubProvider);
  return ref.watch(matchesProvider).whenData<FootballMatch?>((r) {
    if (fav == null) return null;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final list = r.data
        .where((m) =>
            !m.isFinished && m.kickoffUtc.isAfter(cutoff) && m.involves(fav))
        .toList()
      ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
    return list.isEmpty ? null : list.first;
  });
});

/// Detak 1 detik untuk countdown (berhenti otomatis saat tidak dipakai).
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  while (true) {
    yield DateTime.now();
    await Future.delayed(const Duration(seconds: 1));
  }
});
