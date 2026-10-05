import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/football/data/models.dart';

/// Fixture mengikuti respons football-data.org v4 yang dipangkas. Tujuannya
/// mengunci parser terhadap bentuk data nyata, termasuk data yang tidak lengkap
/// dan satu item yang rusak total.
void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    fixture = jsonDecode(
            File('test/fixtures/football_data_v4.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  List<Map<String, dynamic>> matches() =>
      (fixture['matches'] as List).cast<Map<String, dynamic>>();

  List<PlClub> assetClubs() =>
      (jsonDecode(File('assets/data/pl_clubs.json').readAsStringSync()) as List)
          .map((e) => PlClub.fromJson(e as Map<String, dynamic>))
          .toList();

  group('football-data.org v4: respons nyata dipangkas', () {
    test('laga yang sudah selesai punya skor dan status FINISHED', () {
      final m = FootballMatch.tryParse(matches()[0]);
      expect(m, isNotNull);
      expect(m!.id, 1);
      expect(m.kickoffUtc, DateTime.utc(2026, 8, 15, 14));
      expect(m.kickoffUtc.isUtc, isTrue, reason: 'kicker harus disimpan UTC');
      expect(m.status, 'FINISHED');
      expect(m.isFinished, isTrue);
      expect(m.hasScore, isTrue);
      expect(m.homeScore, 2);
      expect(m.awayScore, 1);
      expect(m.homeTla, 'ARS');
      expect(m.matchday, 1);
    });

    test('laga yang belum main tidak punya skor meski blok score ada', () {
      final m = FootballMatch.tryParse(matches()[1])!;
      expect(m.status, 'SCHEDULED');
      expect(m.hasScore, isFalse);
      expect(m.homeScore, isNull);
      expect(m.awayScore, isNull);
      expect(m.isFinished, isFalse);
      expect(m.isOngoing, isFalse);
    });

    test('status kosong dibaca SCHEDULED, bukan string kosong', () {
      final m = FootballMatch.tryParse(matches()[3])!;
      expect(m.status, 'SCHEDULED');
    });

    test('satu item rusak dibuang tanpa menggagalkan daftar', () {
      final parsed = matches()
          .map(FootballMatch.tryParse)
          .whereType<FootballMatch>()
          .toList();
      // 5 item di fixture, 1 di antaranya rusak (tidak ada utcDate).
      expect(parsed, hasLength(4));
      expect(parsed.map((m) => m.id), isNot(contains(3)));
    });

    test('shortName dan tla yang hilang diisi dari nama', () {
      final m = FootballMatch.tryParse(matches()[3])!;
      expect(m.homeName, 'Brighton & Hove Albion FC');
      expect(m.homeShort, 'Brighton & Hove Albion FC');
      expect(m.homeTla, isNull);
      expect(m.awayName, 'Newcastle United FC');
    });

    test('nama tim dari API dengan akhiran FC tetap cocok ke klub lokal', () {
      final clubs = assetClubs();
      final brighton = clubs.firstWhere((c) => c.key == 'brighton');
      final newcastle = clubs.firstWhere((c) => c.key == 'newcastle');
      final m = FootballMatch.tryParse(matches()[3])!;
      // Tanpa tla pun alias "brighton" dan "newcastle" harus mencocokkan.
      expect(m.involves(brighton), isTrue);
      expect(m.involves(newcastle), isTrue);
      expect(m.involves(clubs.firstWhere((c) => c.key == 'arsenal')), isFalse);
    });

    test('klub yang tidak ada di 20 klub 2026-27 tidak cocok ke siapa pun', () {
      final clubs = assetClubs();
      final relegated = FootballMatch.tryParse(matches()[4])!;
      for (final c in clubs) {
        expect(relegated.involves(c), isFalse,
            reason: '${c.key} tidak boleh cocok dengan ${relegated.homeName}');
      }
    });
  });

  group('status inplace lain', () {
    Map<String, dynamic> base(Map<String, Object?> extra) => {
          'id': 99,
          'utcDate': '2026-08-15T14:00:00Z',
          'homeTeam': {'name': 'Arsenal', 'shortName': 'Arsenal', 'tla': 'ARS'},
          'awayTeam': {'name': 'Chelsea', 'shortName': 'Chelsea', 'tla': 'CHE'},
          ...extra,
        };

    test('IN_PLAY, PAUSED, dan LIVE dibaca sedang berlangsung', () {
      for (final s in ['IN_PLAY', 'PAUSED', 'LIVE']) {
        final m = FootballMatch.tryParse(base({'status': s}))!;
        expect(m.isOngoing, isTrue, reason: s);
        expect(m.isFinished, isFalse, reason: s);
      }
    });

    test('AWARDED atau TIMED_OUT tidak dianggap sedang main', () {
      for (final s in ['AWARDED', 'TIMED_OUT', 'POSTPONED', 'FINISHED']) {
        final m = FootballMatch.tryParse(base({'status': s}))!;
        expect(m.isOngoing, isFalse, reason: s);
      }
    });

    test('skorAway yang hanya terisi sebagian tidak dianggap punya skor', () {
      final m = FootballMatch.tryParse(base({
        'status': 'IN_PLAY',
        'score': {
          'fullTime': {'home': 1, 'away': null}
        },
      }))!;
      expect(m.homeScore, 1);
      expect(m.awayScore, isNull);
      expect(m.hasScore, isFalse,
          reason:
              'skor setengah filled dipakai prediksi, bukan ditulis sebagai hasil akhir');
    });
  });

  group('klasemen', () {
    test('baris lengkap terbaca apa adanya', () {
      final r = StandingRow.tryParse(
          (fixture['standings'] as List)[0] as Map<String, dynamic>)!;
      expect(r.position, 1);
      expect(r.played, 4);
      expect(r.won, 4);
      expect(r.draw, 0);
      expect(r.lost, 0);
      expect(r.goalDiff, 6);
      expect(r.points, 12);
      expect(r.teamShort, 'Arsenal');
      expect(r.tla, 'ARS');
    });

    test('baris season baru tanpa playedGames jadi 0, bukan error', () {
      final r = StandingRow.tryParse(
          (fixture['standings'] as List)[3] as Map<String, dynamic>)!;
      expect(r.position, 20);
      expect(r.played, 0);
      expect(r.won, 0);
      expect(r.points, 0);
      expect(r.teamName, 'Sunderland');
    });

    test('baris tanpa tim dibuang', () {
      expect(StandingRow.tryParse({'position': 1, 'points': 3, 'team': null}),
          isNull);
      expect(StandingRow.tryParse({'position': 1, 'points': 3}), isNull);
    });

    test('keempat baris fixture terbaca tanpa kehilangan posisi', () {
      final rows = (fixture['standings'] as List)
          .cast<Map<String, dynamic>>()
          .map(StandingRow.tryParse)
          .whereType<StandingRow>()
          .toList();
      expect(rows, hasLength(4));
      expect(rows.map((r) => r.position), containsAll([1, 2, 3, 20]));
    });
  });

  group('top skor', () {
    test('asisten kosong dibaca null, bukan 0', () {
      final rows = (fixture['scorers'] as List)
          .cast<Map<String, dynamic>>()
          .map(ScorerRow.tryParse)
          .whereType<ScorerRow>()
          .toList();
      expect(rows, hasLength(2));
      final saka = rows.firstWhere((r) => r.player == 'Bukayo Saka');
      expect(saka.goals, 5);
      expect(saka.assists, 2);
      expect(saka.teamShort, 'Arsenal');
      final haaland = rows.firstWhere((r) => r.player == 'Erling Haaland');
      expect(haaland.goals, 6);
      expect(haaland.assists, isNull);
    });

    test('pemain tanpa tim dibuang tanpa menggagalkan daftar', () {
      final withTeam = ScorerRow.tryParse(
          (fixture['scorers'] as List)[0] as Map<String, dynamic>);
      expect(withTeam, isNotNull);
      expect(
          ScorerRow.tryParse(
              (fixture['scorers'] as List)[2] as Map<String, dynamic>),
          isNull);
    });
  });

  group('PlClub.isTeam untuk 20 klub 2026-27', () {
    // Nama tim apa adanya di respons football-data.org (varian "X FC").
    const apiNames = <String, String>{
      'arsenal': 'Arsenal FC',
      'aston_villa': 'Aston Villa FC',
      'bournemouth': 'AFC Bournemouth',
      'brentford': 'Brentford FC',
      'brighton': 'Brighton & Hove Albion FC',
      'chelsea': 'Chelsea FC',
      'coventry': 'Coventry City FC',
      'crystal_palace': 'Crystal Palace FC',
      'everton': 'Everton FC',
      'fulham': 'Fulham FC',
      'hull': 'Hull City FC',
      'ipswich': 'Ipswich Town FC',
      'leeds': 'Leeds United FC',
      'liverpool': 'Liverpool FC',
      'man_city': 'Manchester City FC',
      'man_united': 'Manchester United FC',
      'newcastle': 'Newcastle United FC',
      'forest': 'Nottingham Forest FC',
      'sunderland': 'Sunderland FC',
      'tottenham': 'Tottenham Hotspur FC',
    };

    test('data aset berisi tepat 20 klub dan setiap kunci punya nama API', () {
      final clubs = assetClubs();
      expect(clubs, hasLength(20));
      expect(clubs.map((c) => c.key).toSet(), apiNames.keys.toSet());
    });

    test('setiap klub dikenali dari nama tim di respons API', () {
      final clubs = assetClubs();
      for (final c in clubs) {
        expect(c.isTeam(apiNames[c.key]!, null), isTrue,
            reason: 'nama API "${apiNames[c.key]}" harus cocok ke ${c.key}');
      }
    });

    test('nama lokal persis juga dikenali', () {
      for (final c in assetClubs()) {
        expect(c.isTeam(c.name, null), isTrue, reason: c.key);
        expect(c.isTeam(c.name.toUpperCase(), null), isTrue,
            reason: 'pencocokan nama harus tahan huruf besar: ${c.key}');
      }
    });

    test('tiga klub degradasi tidak cocok ke klub mana pun', () {
      // Klub yang tidak ada di 20 klub 2026-27. Kalau nama seperti ini sampai
      // cocok, berarti alias terlalu longgar dan Pundit/Lens salah klub.
      const degraded = [
        'Wolverhampton Wanderers',
        'West Ham United',
        'Stoke City'
      ];
      for (final c in assetClubs()) {
        for (final name in degraded) {
          expect(c.isTeam(name, null), isFalse, reason: '$name vs ${c.key}');
          expect(c.isTeam(name, 'ZZZ'), isFalse,
              reason: '$name dengan tla asing vs ${c.key}');
        }
      }
    });

    test('satu nama tim tidak cocok ke klub yang salah', () {
      final clubs = assetClubs();
      PlClub club(String key) => clubs.firstWhere((c) => c.key == key);
      expect(club('man_city').isTeam('Manchester United FC', null), isFalse);
      expect(club('tottenham').isTeam('Manchester United FC', null), isFalse);
      expect(club('tottenham').isTeam('Spurs', null), isTrue,
          reason: 'alias "spurs" harus tetap berguna untuk Lens');
      expect(club('man_united').isTeam('Spurs', null), isFalse,
          reason: '"Spurs" bukan Manchester United');
    });
  });

  group('PlClub.isTeam memakai tla sebagai jalan pintas', () {
    final clubs = assetClubs();
    PlClub club(String key) => clubs.firstWhere((c) => c.key == key);

    test('tla yang cocok langsung dianggap benar walau nama berbeda', () {
      expect(club('arsenal').isTeam('The Gunners', 'ARS'), isTrue);
      expect(club('liverpool').isTeam('Liverpool FC', 'LIV'), isTrue);
    });

    test('tla tidak case sensitive', () {
      expect(club('chelsea').isTeam('The Blues', 'che'), isTrue);
    });

    test('tla yang tidak cocok tidak membuat nama yang mirip ikut benar', () {
      // "Stoke City" memuat kata city, tapi bukan Manchester City.
      expect(club('man_city').isTeam('Stoke City', 'STK'), isFalse);
    });
  });

  group('PlClub.fromJson', () {
    test('semua klub punya koordinat stadion dan warna ARGB', () {
      for (final c in assetClubs()) {
        expect(c.lat, inInclusiveRange(-90, 90), reason: c.key);
        expect(c.lng, inInclusiveRange(-180, 180), reason: c.key);
        expect(c.color, greaterThan(0xFF000000), reason: c.key);
        expect(c.color, lessThan(0xFFFFFFFF), reason: c.key);
        expect(c.stadium, isNotEmpty, reason: c.key);
        expect(c.tla.length, 3, reason: c.key);
        expect(c.aliases, isNotEmpty,
            reason: '${c.key} butuh alias untuk Lens');
      }
    });
  });
}
