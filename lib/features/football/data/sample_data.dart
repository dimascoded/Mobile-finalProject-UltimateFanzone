import 'models.dart';

/// DATA CONTOH untuk pengembangan/demo tanpa API key. BUKAN jadwal atau hasil resmi.
/// UI wajib menampilkan banner "Data contoh" saat sumbernya DataSource.sample.
///
/// Isinya sengaja dibuat deterministik (tidak diacak): jadwal dihitung
/// relatif terhadap hari ini sehingga demo selalu punya 4 laga lampau dan 6
/// laga mendatang, apa pun tanggal build-nya.
class SampleData {
  // name, short, tla
  static const _teams = <List<String>>[
    ['Arsenal FC', 'Arsenal', 'ARS'],
    ['Chelsea FC', 'Chelsea', 'CHE'],
    ['Liverpool FC', 'Liverpool', 'LIV'],
    ['Manchester City FC', 'Man City', 'MCI'],
    ['Manchester United FC', 'Man United', 'MUN'],
    ['Tottenham Hotspur FC', 'Tottenham', 'TOT'],
    ['Newcastle United FC', 'Newcastle', 'NEW'],
    ['Aston Villa FC', 'Aston Villa', 'AVL'],
    ['Leeds United FC', 'Leeds', 'LEE'],
    ['Everton FC', 'Everton', 'EVE'],
    ['Brighton & Hove Albion FC', 'Brighton', 'BHA'],
    ['Fulham FC', 'Fulham', 'FUL'],
    ['Sunderland AFC', 'Sunderland', 'SUN'],
    ['Crystal Palace FC', 'Crystal Palace', 'CRY'],
    ['Brentford FC', 'Brentford', 'BRE'],
    ['Nottingham Forest FC', 'Nottingham Forest', 'NOT'],
    ['Coventry City FC', 'Coventry', 'COV'],
    ['Hull City AFC', 'Hull City', 'HUL'],
    ['Ipswich Town FC', 'Ipswich', 'IPS'],
    ['AFC Bournemouth', 'Bournemouth', 'BOU'],
  ];

  /// Jadwal contoh: 10 laga (id 900000+), 4 lampau dan 6 mendatang.
  ///
  /// Kickoff dihitung dari tengah malam UTC hari ini + jam tetap (12, 14,
  /// 16, atau 19 UTC), jadi contoh selalu punya masa lalu dan masa depan.
  /// Laga lampau berstatus `FINISHED` dan punya skor pseudo-acak; laga
  /// mendatang berstatus `TIMED` tanpa skor.
  static List<FootballMatch> matches() {
    final now = DateTime.now().toUtc();
    final day0 = DateTime.utc(now.year, now.month, now.day);
    const hours = [12, 14, 16, 19];
    return [
      for (var i = 0; i < 10; i++)
        () {
          final h = _teams[i * 2];
          final a = _teams[i * 2 + 1];
          final offsetDays = i - 4; // 4 laga lampau, 6 laga mendatang
          final finished = offsetDays < 0;
          return FootballMatch(
            id: 900000 + i,
            kickoffUtc:
                day0.add(Duration(days: offsetDays, hours: hours[i % 4])),
            status: finished ? 'FINISHED' : 'TIMED',
            matchday: 1 + i ~/ 2,
            homeName: h[0],
            awayName: a[0],
            homeShort: h[1],
            awayShort: a[1],
            homeTla: h[2],
            awayTla: a[2],
            homeScore: finished ? (i * 3 + 1) % 4 : null,
            awayScore: finished ? (i * 2) % 3 : null,
          );
        }(),
    ];
  }

  /// Klasemen contoh untuk 20 klub: setiap tim dadurch 8 laga, poin = 3 per
  /// menang + 1 per seri, lalu diurutkan berdasarkan poin (tie dipecah
  /// dengan urutan tetap klub) dan diberi nomor posisi 1..20.
  static List<StandingRow> standings() {
    final rows = <StandingRow>[
      for (var i = 0; i < _teams.length; i++)
        () {
          final won = 7 - i ~/ 3;
          final draw = i % 2;
          final lost = 8 - won - draw;
          return StandingRow(
            position: 0,
            teamName: _teams[i][0],
            teamShort: _teams[i][1],
            tla: _teams[i][2],
            played: 8,
            won: won,
            draw: draw,
            lost: lost,
            goalDiff: 12 - i,
            points: won * 3 + draw,
          );
        }(),
    ]..sort((a, b) => b.points.compareTo(a.points));
    return [
      for (var i = 0; i < rows.length; i++)
        StandingRow(
          position: i + 1,
          teamName: rows[i].teamName,
          teamShort: rows[i].teamShort,
          tla: rows[i].tla,
          played: rows[i].played,
          won: rows[i].won,
          draw: rows[i].draw,
          lost: rows[i].lost,
          goalDiff: rows[i].goalDiff,
          points: rows[i].points,
        ),
    ];
  }

  /// Lima pencetak gol teratas contoh dengan nama pemain generik
  /// ("Pemain Contoh 1" dst.), gol menurun dari 9 ke 5 dan 3 assist.
  static List<ScorerRow> scorers() => [
        for (var i = 0; i < 5; i++)
          ScorerRow(
            player: 'Pemain Contoh ${i + 1}',
            teamName: _teams[i][0],
            teamShort: _teams[i][1],
            tla: _teams[i][2],
            goals: 9 - i,
            assists: 3,
          ),
      ];
}
