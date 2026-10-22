import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/football_repository.dart';
import '../data/models.dart';

// ---------- Klub & tim favorit ----------

/// Daftar klub Premier League yang tersedia di aplikasi.
///
/// Dimuat dari aset lokal `assets/data/pl_clubs.json` lewat
/// [ClubRepository.load], jadi tidak butuh jaringan dan selalu tersedia
/// (meski `AsyncValue`-nya sempat `loading` saat aset dibaca). Data ini
/// sumber kebenaran untuk koordinat stadion, singkatan tim, dan kunci klub
/// yang dipakai tim favorit, stamp, serta kartu klub.
final clubsProvider = FutureProvider<List<PlClub>>(
    (ref) => ref.watch(clubRepositoryProvider).load());

/// Notifier tim favorit pengguna.
///
/// State-nya `String?` berisi kunci klub (mis. `arsenal`); null berarti belum
/// ada tim favorit. Nilai disimpan per pengguna di Hive `app_cache` dengan
/// kunci `favorite_team_<userId>` (dibaca lewat
/// [AuthRepository.readUserScopedValue], yang sekaligus mengadopsi nilai
/// legacy global) dan dicerminkan ke metadata Supabase lewat
/// [AuthRepository.saveProfilePrefs].
///
/// Notifier tidak `autoDispose`, jadi tidak wajib cek `mounted` setelah
/// `await` (aturan §3.5 hanya berlaku untuk notifier `autoDispose`).
class FavoriteTeamNotifier extends StateNotifier<String?> {
  FavoriteTeamNotifier(this._repo) : super(_repo.favoriteKey());
  final ClubRepository _repo;

  /// Simpan tim favorit baru.
  ///
  /// Menolak (return false) bila belum ada sesi pengguna, sehingga pilihan
  /// tidak pernah ditulis ke storage bersama. Nilai baru disimpan ke Hive per
  /// pengguna lalu dicoba disalin ke metadata akun; nilai kembalian
  /// menandakan berhasil/tidaknya penulisan ke cloud.
  Future<bool> set(String key) async {
    if (_repo.currentUserId == null) return false;
    state = key;
    return _repo.saveFavoriteWithCloudStatus(key);
  }
}

/// Kunci klub tim favorit aktif (mis. `arsenal`), null bila belum dipilih.
///
/// StateProvider biasa (bukan `autoDispose`) karena dipakai lintas layar
/// (filter jadwal, stamp, kartu klub, Pundit, navigasi stadion).
final favoriteKeyProvider =
    StateNotifierProvider<FavoriteTeamNotifier, String?>(
        (ref) => FavoriteTeamNotifier(ref.watch(clubRepositoryProvider)));

/// Objek klub lengkap untuk tim favorit aktif.
///
/// Provider turunan: mencocokkan kunci dari [favoriteKeyProvider] dengan
/// daftar [clubsProvider]. Mengembalikan null saat belum ada tim favorit
/// atau daftar klub belum termuat. Tanpa efek samping.
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

/// Jadwal dan hasil pertandingan Premier League.
///
/// Provider async yang memanggil API football-data.org lewat
/// [FootballRepository.matches]; hasilnya dibungkus [FootballResult] yang
/// membawa asal data (`live`, `cache`, atau `sample`) dan waktu pengambilan.
/// Cache respons disimpan di Hive `app_cache` (kunci `fd_matches` dan
/// `fd_matches_at`) dengan TTL 15 menit, atau 3 menit bila ada laga yang
/// baru saja kickoff. Tanpa `FOOTBALL_API_KEY` yang dipakai adalah data
/// contoh.
final matchesProvider = FutureProvider<FootballResult<List<FootballMatch>>>(
    (ref) => ref.watch(footballRepositoryProvider).matches());

/// Klasemen Premier League.
///
/// Provider async dari [FootballRepository.standings]; cache di Hive
/// `app_cache` (kunci `fd_standings` dan `fd_standings_at`). Mengembalikan
/// baris klasemen per tim beserta poin dan posisi.
final standingsProvider = FutureProvider<FootballResult<List<StandingRow>>>(
    (ref) => ref.watch(footballRepositoryProvider).standings());

/// Daftar pencetak gol Premier League.
///
/// Provider async dari [FootballRepository.scorers]; cache di Hive
/// `app_cache` (kunci `fd_scorers` dan `fd_scorers_at`).
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
///
/// Memberi jalan pintas untuk tombol "muat ulang": menghapus stempel waktu
/// cache `fd_matches`, `fd_standings`, dan `fd_scorers` di Hive `app_cache`
/// lalu meng-invalidate ketiga provider supaya permintaan baru ke
/// football-data.org dijalankan. Nilai balik adalah future yang selesai saat
/// pemanggilan selesai; tidak ada navigasi atau notifikasi.
final footballRefreshProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(footballRepositoryProvider).expire();
    ref.invalidate(matchesProvider);
    ref.invalidate(standingsProvider);
    ref.invalidate(scorersProvider);
  };
});

// ---------- Filter & pencarian jadwal ----------

/// Filter jadwal yang sedang aktif di layar jadwal.
enum MatchFilter { upcoming, favorite, finished, all }

/// Filter jadwal aktif (default `upcoming`).
///
/// State lokal UI dengan `autoDispose`: pilihan filter hilang saat layar
/// ditutup.
final matchFilterProvider =
    StateProvider.autoDispose<MatchFilter>((ref) => MatchFilter.upcoming);

/// Teks pencarian jadwal (nama tim home atau away).
///
/// State lokal UI dengan `autoDispose`; di-reset ke string kosong saat
/// provider di-dispose.
final matchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Jadwal setelah filter dan pencarian diterapkan.
///
/// Provider turunan dari [matchesProvider]: menggabungkan filter
/// [matchFilterProvider], pencarian [matchQueryProvider], dan tim favorit
/// [favoriteClubProvider]. Pencarian mencocokkan nama tim home/away
/// (case-insensitive). Fase laga (`upcoming`, `live`, `finished`,
/// `awaitingResult`, `cancelled`) dihitung terhadap waktu UTC sekarang, jadi
/// daftar bisa berubah sendiri seiring waktu tanpa fetch ulang. Pengurutan:
/// kronologis untuk agenda, terbalik (terbaru dulu) untuk riwayat.
/// `autoDispose` dan tanpa efek samping.
final filteredMatchesProvider =
    Provider.autoDispose<AsyncValue<FootballResult<List<FootballMatch>>>>(
        (ref) {
  final filter = ref.watch(matchFilterProvider);
  final q = ref.watch(matchQueryProvider).toLowerCase().trim();
  final fav = ref.watch(favoriteClubProvider);
  final now = DateTime.now().toUtc();

  return ref.watch(matchesProvider).whenData((r) {
    final list = r.data.where((m) {
      if (q.isNotEmpty &&
          !m.homeName.toLowerCase().contains(q) &&
          !m.awayName.toLowerCase().contains(q)) {
        return false;
      }
      final phase = m.phaseAt(now);
      switch (filter) {
        case MatchFilter.upcoming:
          return phase == MatchPhase.upcoming || phase == MatchPhase.live;
        case MatchFilter.finished:
          return phase == MatchPhase.finished ||
              phase == MatchPhase.awaitingResult ||
              phase == MatchPhase.cancelled;
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
///
/// Provider turunan dari [matchesProvider]: mencari laga yang masih `upcoming`
/// atau `live` dan melibatkan tim favorit, lalu mengambil yang paling dekat
/// kickoff-nya. Mengembalikan null bila belum ada tim favorit atau tidak ada
/// laga yang cocok. Tanpa efek samping.
final nextMatchProvider = Provider<AsyncValue<FootballMatch?>>((ref) {
  final fav = ref.watch(favoriteClubProvider);
  return ref.watch(matchesProvider).whenData<FootballMatch?>((r) {
    if (fav == null) return null;
    final now = DateTime.now().toUtc();
    final list = r.data
        .where((m) {
          final phase = m.phaseAt(now);
          final soon = phase == MatchPhase.upcoming || phase == MatchPhase.live;
          return soon && m.involves(fav);
        })
        .toList()
      ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
    return list.isEmpty ? null : list.first;
  });
});

/// Detak 1 detik untuk countdown (berhenti otomatis saat tidak dipakai).
///
/// Stream `autoDispose` yang memancarkan waktu lokal saat ini setiap detik;
/// dipakai layar detail laga untuk hitung mundur kickoff. Stream berhenti
/// otomatis saat tidak ada layar yang menonton, sehingga tidak membebani
/// aplikasi di latar belakang. Tanpa efek samping.
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  while (true) {
    yield DateTime.now();
    await Future.delayed(const Duration(seconds: 1));
  }
});
