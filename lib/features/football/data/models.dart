import 'package:flutter/material.dart' show Color;

/// Klub Premier League 2026-27 (data aset lokal, termasuk stadion & koordinat).
///
/// Data diambil dari `assets/data/pl_clubs.json`, bukan dari API, jadi nama,
/// stadion, dan koordinat selalu konsisten walau jaringan mati.
class PlClub {
  /// Membuat data klub lengkap.
  const PlClub({
    required this.key,
    required this.name,
    required this.shortName,
    required this.tla,
    required this.city,
    required this.stadium,
    required this.lat,
    required this.lng,
    required this.color,
    required this.aliases,
  });

  /// Kode klub stabil (mis. `ars`), dipakai sebagai kunci cache per klub.
  final String key, name, shortName, tla, city, stadium;

  /// Koordinat stadion (WGS84) untuk fitur Stadium Pointer.
  final double lat, lng;

  /// Warna klub dalam format ARGB (dipakai sebagai `0xFFRRGGBB`).
  final int color;

  /// Nama alternatif untuk pencocokan tim yang toleran (lihat [isTeam]).
  final List<String> aliases;

  /// Warna klub sebagai objek [Color] Flutter.
  Color get colorValue => Color(color);

  /// Cocokkan dengan nama tim dari API (toleran terhadap akhiran "FC"/"AFC").
  ///
  /// Dua jalur: cocokkan kode tim (TLA) persis, atau cari salah satu
  /// [aliases] di dalam nama tim (kecil semua). Dipakai juga untuk mencocokkan
  /// klub dengan teks OCR pada struk.
  bool isTeam(String teamName, String? teamTla) {
    if (teamTla != null && teamTla.toUpperCase() == tla) return true;
    final n = teamName.toLowerCase();
    return aliases.any(n.contains);
  }

  /// Parse satu entri dari `assets/data/pl_clubs.json`.
  ///
  /// Melempar galat bila field wajib tidak ada atau salah tipe — aset ini
  /// dikemas saat build, jadi galat di sini berarti aset rusak, bukan data
  /// pengguna yang perlu ditoleransi.
  factory PlClub.fromJson(Map<String, dynamic> j) => PlClub(
        key: j['key'],
        name: j['name'],
        shortName: j['shortName'],
        tla: j['tla'],
        city: j['city'],
        stadium: j['stadium'],
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        color: int.parse('0xFF${j['color']}'),
        aliases: List<String>.from(j['aliases'] as List),
      );
}

/// Satu pertandingan (diparse toleran dari respons football-data.org v4).
///
/// Struktur respons sumber: `homeTeam`/`awayTeam` (nama, shortName, tla,
/// crest) dan `score.fullTime.home`/`away` untuk skor.
class FootballMatch {
  /// Membuat model pertandingan.
  const FootballMatch({
    required this.id,
    required this.kickoffUtc,
    required this.status,
    required this.matchday,
    required this.homeName,
    required this.awayName,
    required this.homeShort,
    required this.awayShort,
    this.homeTla,
    this.awayTla,
    this.homeCrest,
    this.awayCrest,
    this.homeScore,
    this.awayScore,
  });

  /// Id laga di football-data.org (dipakai juga sebagai id notifikasi).
  final int id;

  /// Waktu kickoff; selalu UTC.
  final DateTime kickoffUtc;

  /// Status dari API (`SCHEDULED`, `TIMED`, `IN_PLAY`, `FINISHED`, ...).
  final String status, homeName, awayName, homeShort, awayShort;

  /// Nomor matchday; null bila API tidak mengirimnya.
  final int? matchday;

  /// Skor akhir kedua tim; null selama laga belum selesai.
  final int? homeScore, awayScore;

  /// Kode tim tiga huruf (mis. `ARS`); bisa null.
  final String? homeTla, awayTla;

  /// URL crest dari football-data.org; null pada data contoh / cache lama.
  final String? homeCrest, awayCrest;

  /// True bila laga sudah selesai dan skornya final.
  bool get isFinished => status == 'FINISHED';

  /// True bila laga sedang berjalan (termasuk jeda%).
  bool get isOngoing =>
      status == 'IN_PLAY' || status == 'PAUSED' || status == 'LIVE';

  /// True bila kedua skor sudah tersedia.
  bool get hasScore => homeScore != null && awayScore != null;

  /// Fase laga pada [nowUtc]. Dipakai untuk memutuskan label status dan filter
  /// "mendatang" tanpa bergantung pada jam perangkat secara implisit.
  ///
  /// Laga yang lewat 150 menit sejak kickoff tapi belum `FINISHED` dianggap
  /// [MatchPhase.awaitingResult], bukan masih [MatchPhase.live], karena skor
  /// akhirnya belum tersedia.
  MatchPhase phaseAt(DateTime nowUtc) {
    if (status == 'POSTPONED' ||
        status == 'CANCELLED' ||
        status == 'SUSPENDED') {
      return MatchPhase.cancelled;
    }
    if (status == 'FINISHED' || status == 'AWARDED') {
      return MatchPhase.finished;
    }
    if (isOngoing) return MatchPhase.live;
    if (kickoffUtc.isAfter(nowUtc)) return MatchPhase.upcoming;
    final elapsed = nowUtc.difference(kickoffUtc);
    return elapsed < const Duration(minutes: 150)
        ? MatchPhase.live
        : MatchPhase.awaitingResult;
  }

  /// True bila klub [c] ikut bermain di laga ini.
  bool involves(PlClub c) =>
      c.isTeam(homeName, homeTla) || c.isTeam(awayName, awayTla);

  /// Parse satu objek `matches[]` dari football-data.org v4.
  ///
  /// Mengembalikan null bila data rusak (missing/wrong type) supaya satu item
  /// cacat tidak menghapus seluruh daftar; pemanggil memfilter null.
  static FootballMatch? tryParse(Map<String, dynamic> j) {
    try {
      final home = Map<String, dynamic>.from(j['homeTeam'] as Map);
      final away = Map<String, dynamic>.from(j['awayTeam'] as Map);
      final ft = (j['score'] as Map?)?['fullTime'] as Map?;
      String nameOf(Map<String, dynamic> t) =>
          '${t['name'] ?? t['shortName'] ?? '?'}';
      String shortOf(Map<String, dynamic> t) =>
          '${t['shortName'] ?? t['name'] ?? '?'}';
      return FootballMatch(
        id: (j['id'] as num).toInt(),
        kickoffUtc: DateTime.parse(j['utcDate'] as String).toUtc(),
        status: '${j['status'] ?? 'SCHEDULED'}',
        matchday: (j['matchday'] as num?)?.toInt(),
        homeName: nameOf(home),
        awayName: nameOf(away),
        homeShort: shortOf(home),
        awayShort: shortOf(away),
        homeTla: home['tla'] as String?,
        awayTla: away['tla'] as String?,
        homeCrest: home['crest'] as String?,
        awayCrest: away['crest'] as String?,
        homeScore: (ft?['home'] as num?)?.toInt(),
        awayScore: (ft?['away'] as num?)?.toInt(),
      );
    } catch (_) {
      return null; // satu data rusak tidak boleh menggagalkan seluruh daftar
    }
  }
}

/// Fase laga relatif terhadap waktu sekarang (lihat [FootballMatch.phaseAt]).
enum MatchPhase { upcoming, live, awaitingResult, finished, cancelled }

/// Satu baris klasemen Premier League (dari `standings[].table[]`).
class StandingRow {
  /// Membuat baris klasemen.
  const StandingRow({
    required this.position,
    required this.teamName,
    required this.teamShort,
    this.tla,
    this.crest,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalDiff,
    required this.points,
  });

  /// Posisi di tabel (1 = juara), jumlah laga, menang, seri, kalah, selisih
  /// gol, dan poin.
  final int position, played, won, draw, lost, goalDiff, points;

  /// Nama tim lengkap dan nama singkat.
  final String teamName, teamShort;

  /// Kode tim tiga huruf; bisa null.
  final String? tla;

  /// URL crest dari football-data.org; null pada data contoh / cache lama.
  final String? crest;

  /// Parse satu baris `table[]` dari football-data.org v4.
  ///
  /// Mengembalikan null bila data rusak; angka yang hilang dianggap 0.
  static StandingRow? tryParse(Map<String, dynamic> j) {
    try {
      final t = Map<String, dynamic>.from(j['team'] as Map);
      return StandingRow(
        position: (j['position'] as num).toInt(),
        teamName: '${t['name'] ?? t['shortName'] ?? '?'}',
        teamShort: '${t['shortName'] ?? t['name'] ?? '?'}',
        tla: t['tla'] as String?,
        crest: t['crest'] as String?,
        played: (j['playedGames'] as num?)?.toInt() ?? 0,
        won: (j['won'] as num?)?.toInt() ?? 0,
        draw: (j['draw'] as num?)?.toInt() ?? 0,
        lost: (j['lost'] as num?)?.toInt() ?? 0,
        goalDiff: (j['goalDifference'] as num?)?.toInt() ?? 0,
        points: (j['points'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Satu baris pencetak gol (dari `scorers[]`).
class ScorerRow {
  /// Membuat baris pencetak gol.
  const ScorerRow({
    required this.player,
    required this.teamName,
    required this.teamShort,
    this.tla,
    this.crest,
    required this.goals,
    this.assists,
  });

  /// Nama pemain dan afiliasi timnya.
  final String player, teamName, teamShort;

  /// Kode tim tiga huruf; bisa null.
  final String? tla;

  /// Jumlah gol; assist boleh null bila API tidak mengirimnya.
  final int goals;
  final int? assists;

  /// URL crest dari football-data.org; null pada data contoh / cache lama.
  final String? crest;

  /// Parse satu entri `scorers[]` dari football-data.org v4.
  ///
  /// Mengembalikan null bila data rusak; angka yang hilang dianggap 0.
  static ScorerRow? tryParse(Map<String, dynamic> j) {
    try {
      final p = Map<String, dynamic>.from(j['player'] as Map);
      final t = Map<String, dynamic>.from(j['team'] as Map);
      return ScorerRow(
        player: '${p['name'] ?? '?'}',
        teamName: '${t['name'] ?? t['shortName'] ?? '?'}',
        teamShort: '${t['shortName'] ?? t['name'] ?? '?'}',
        tla: t['tla'] as String?,
        crest: t['crest'] as String?,
        goals: (j['goals'] as num?)?.toInt() ?? 0,
        assists: (j['assists'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
