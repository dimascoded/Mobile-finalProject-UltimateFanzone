import 'package:flutter/material.dart' show Color;

/// Klub Premier League 2026-27 (data aset lokal, termasuk stadion & koordinat).
class PlClub {
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
  final String key, name, shortName, tla, city, stadium;
  final double lat, lng;
  final int color; // ARGB
  final List<String> aliases;

  Color get colorValue => Color(color);

  /// Cocokkan dengan nama tim dari API (toleran terhadap akhiran "FC"/"AFC").
  bool isTeam(String teamName, String? teamTla) {
    if (teamTla != null && teamTla.toUpperCase() == tla) return true;
    final n = teamName.toLowerCase();
    return aliases.any(n.contains);
  }

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
class FootballMatch {
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
    this.homeScore,
    this.awayScore,
  });
  final int id;
  final DateTime kickoffUtc; // selalu UTC
  final String status, homeName, awayName, homeShort, awayShort;
  final int? matchday, homeScore, awayScore;
  final String? homeTla, awayTla;

  bool get isFinished => status == 'FINISHED';
  bool get isOngoing =>
      status == 'IN_PLAY' || status == 'PAUSED' || status == 'LIVE';
  bool get hasScore => homeScore != null && awayScore != null;

  bool involves(PlClub c) =>
      c.isTeam(homeName, homeTla) || c.isTeam(awayName, awayTla);

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
        homeScore: (ft?['home'] as num?)?.toInt(),
        awayScore: (ft?['away'] as num?)?.toInt(),
      );
    } catch (_) {
      return null; // satu data rusak tidak boleh menggagalkan seluruh daftar
    }
  }
}

class StandingRow {
  const StandingRow({
    required this.position,
    required this.teamName,
    required this.teamShort,
    this.tla,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalDiff,
    required this.points,
  });
  final int position, played, won, draw, lost, goalDiff, points;
  final String teamName, teamShort;
  final String? tla;

  static StandingRow? tryParse(Map<String, dynamic> j) {
    try {
      final t = Map<String, dynamic>.from(j['team'] as Map);
      return StandingRow(
        position: (j['position'] as num).toInt(),
        teamName: '${t['name'] ?? t['shortName'] ?? '?'}',
        teamShort: '${t['shortName'] ?? t['name'] ?? '?'}',
        tla: t['tla'] as String?,
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

class ScorerRow {
  const ScorerRow({
    required this.player,
    required this.teamName,
    required this.teamShort,
    this.tla,
    required this.goals,
    this.assists,
  });
  final String player, teamName, teamShort;
  final String? tla;
  final int goals;
  final int? assists;

  static ScorerRow? tryParse(Map<String, dynamic> j) {
    try {
      final p = Map<String, dynamic>.from(j['player'] as Map);
      final t = Map<String, dynamic>.from(j['team'] as Map);
      return ScorerRow(
        player: '${p['name'] ?? '?'}',
        teamName: '${t['name'] ?? t['shortName'] ?? '?'}',
        teamShort: '${t['shortName'] ?? t['name'] ?? '?'}',
        tla: t['tla'] as String?,
        goals: (j['goals'] as num?)?.toInt() ?? 0,
        assists: (j['assists'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}
