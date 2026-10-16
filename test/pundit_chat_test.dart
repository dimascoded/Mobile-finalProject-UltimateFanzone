import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/pundit/data/pundit_chat.dart';
import 'package:ultimate_fanzone/features/pundit/data/pundit_repository.dart';

const _club = PlClub(
  key: 'arsenal',
  name: 'Arsenal',
  shortName: 'Arsenal',
  tla: 'ARS',
  city: 'London',
  stadium: 'Emirates Stadium',
  lat: 51.5549,
  lng: -0.1084,
  color: 0xFFEF0107,
  aliases: ['arsenal'],
);

FootballMatch _match({
  required int id,
  required DateTime kickoffUtc,
  required String status,
  String homeShort = 'Arsenal',
  String awayShort = 'Chelsea',
  String homeName = 'Arsenal',
  String awayName = 'Chelsea',
  int? homeScore,
  int? awayScore,
}) =>
    FootballMatch(
      id: id,
      kickoffUtc: kickoffUtc,
      status: status,
      matchday: 1,
      homeName: homeName,
      awayName: awayName,
      homeShort: homeShort,
      awayShort: awayShort,
      homeScore: homeScore,
      awayScore: awayScore,
    );

void main() {
  group('buildSystemInstruction', () {
    test('memuat nama klub, baris klasemen sendiri, dan kickoff WIB', () {
      const standings = [
        StandingRow(
          position: 1,
          teamName: 'Arsenal',
          teamShort: 'ARS',
          tla: 'ARS',
          played: 10,
          won: 8,
          draw: 1,
          lost: 1,
          goalDiff: 15,
          points: 25,
        ),
        StandingRow(
          position: 2,
          teamName: 'Liverpool',
          teamShort: 'LIV',
          tla: 'LIV',
          played: 10,
          won: 7,
          draw: 2,
          lost: 1,
          goalDiff: 12,
          points: 23,
        ),
      ];
      final last5 = [
        _match(
          id: 1,
          kickoffUtc: DateTime.utc(2026, 9, 1, 14),
          status: 'FINISHED',
          homeScore: 2,
          awayScore: 1,
        ),
      ];
      final upcoming = [
        _match(
          id: 2,
          kickoffUtc: DateTime.utc(2026, 10, 24, 14, 30),
          status: 'SCHEDULED',
          homeShort: 'Arsenal',
          awayShort: 'Everton',
          awayName: 'Everton',
        ),
      ];

      final text = buildSystemInstruction(
        club: _club,
        standings: standings,
        last5: last5,
        upcoming: upcoming,
      );

      expect(text, contains('Arsenal'));
      expect(text, contains('1. Arsenal (ARS) - 25 poin'));
      expect(text, contains('Liga Premier 2026-27'));
      expect(text, contains('WIB'));
      expect(text, contains('21:30'));
    });

    test('menulis "data belum tersedia" saat semua daftar kosong', () {
      final text = buildSystemInstruction(
        club: _club,
        standings: const [],
        last5: const [],
        upcoming: const [],
      );
      final count = 'data belum tersedia'.allMatches(text).length;
      expect(count, greaterThanOrEqualTo(3));
    });

    test('memuat aturan anti judi dan anti instruksi', () {
      final text = buildSystemInstruction(
        club: _club,
        standings: const [],
        last5: const [],
        upcoming: const [],
      );
      expect(text, contains('taruhan'));
      expect(text, contains('instruksi'));
      expect(text.toLowerCase(), contains('120 kata'));
    });
  });

  group('trimTurns', () {
    ChatMessage msg(String role, String text, int minute) => ChatMessage(
          role: role,
          text: text,
          at: DateTime.utc(2026, 1, 1).add(Duration(minutes: minute)),
        );

    test('kosong menghasilkan daftar kosong', () {
      expect(trimTurns(const []), isEmpty);
    });

    test('dibuang agar dimulai dan diakhiri giliran user', () {
      final turns = trimTurns([
        msg('model', 'awal nyasar', 0),
        msg('user', 'a', 1),
        msg('model', 'b', 2),
        msg('user', 'c', 3),
        msg('model', 'd', 4),
      ]);
      expect(turns.first.role, 'user');
      expect(turns.last.role, 'user');
      expect(turns.map((t) => t.text).toList(), ['a', 'b', 'c']);
    });

    test('menghormati maxTurns', () {
      final messages = [
        for (var i = 0; i < 14; i++) msg(i.isEven ? 'user' : 'model', 't$i', i),
      ];
      final turns = trimTurns(messages, maxTurns: 10);
      expect(turns.length, lessThanOrEqualTo(10));
      expect(turns.first.role, 'user');
      expect(turns.last.role, 'user');
    });

    test('menghormati maxChars dan tetap valid', () {
      final messages = [
        for (var i = 0; i < 6; i++)
          msg(i.isEven ? 'user' : 'model', 'x' * 100, i),
      ];
      final turns = trimTurns(messages, maxChars: 250);
      final total = turns.fold<int>(0, (sum, t) => sum + t.text.length);
      expect(total, lessThanOrEqualTo(250));
      expect(turns, isNotEmpty);
      expect(turns.first.role, 'user');
      expect(turns.last.role, 'user');
    });
  });

  group('ChatMessage JSON', () {
    test('round trip', () {
      final m = ChatMessage(
        role: 'model',
        text: 'halo',
        at: DateTime.utc(2026, 3, 4, 5, 6, 7),
      );
      final back = ChatMessage.fromJson(jsonDecode(jsonEncode(m.toJson())));
      expect(back, isNotNull);
      expect(back!.role, 'model');
      expect(back.text, 'halo');
      expect(back.at, m.at);
    });

    test('toleran terhadap data rusak', () {
      expect(ChatMessage.fromJson(null), isNull);
      expect(ChatMessage.fromJson('bukan map'), isNull);
      expect(ChatMessage.fromJson(42), isNull);
      expect(ChatMessage.fromJson({'role': 'user'}), isNull);
      expect(ChatMessage.fromJson({'text': 'hai'}), isNull);
      expect(ChatMessage.fromJson({'role': 'x', 'text': 'hai'}), isNull);

      final recovered = ChatMessage.fromJson({
        'role': 'user',
        'text': 'hai',
        'at': 'bukan-tanggal',
      });
      expect(recovered, isNotNull);
      expect(recovered!.text, 'hai');
    });
  });

  group('PunditRepository chat storage', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sgt_pundit_chat');
      Hive.init(dir.path);
      HiveService.cache = await Hive.openBox<String>('pundit_chat_test');
    });

    tearDown(() async {
      await HiveService.cache.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    ChatMessage msg(int i) => ChatMessage(
          role: i.isEven ? 'user' : 'model',
          text: 'm$i',
          at: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        );

    test('menyimpan paling banyak 30 pesan terakhir', () async {
      final repo = PunditRepository();
      await repo.saveChat('arsenal', [for (var i = 0; i < 35; i++) msg(i)]);

      final loaded = repo.loadChat('arsenal');
      expect(loaded.length, 30);
      expect(loaded.first.text, 'm5');
      expect(loaded.last.text, 'm34');
    });

    test('riwayat terpisah per klub', () async {
      final repo = PunditRepository();
      await repo.saveChat('arsenal', [for (var i = 0; i < 5; i++) msg(i)]);
      await repo.saveChat('chelsea', [msg(0)]);

      expect(repo.loadChat('arsenal').length, 5);
      expect(repo.loadChat('chelsea').length, 1);
    });

    test('data rusak dimuat sebagai daftar kosong', () async {
      final repo = PunditRepository();
      await HiveService.cache.put('pundit_chat_arsenal', 'bukan json');
      expect(repo.loadChat('arsenal'), isEmpty);
      await HiveService.cache.put('pundit_chat_arsenal', '{"bukan":"list"}');
      expect(repo.loadChat('arsenal'), isEmpty);
    });

    test('clearCache menghapus riwayat chat (logout)', () async {
      final repo = PunditRepository();
      await repo.saveChat('arsenal', [msg(0)]);
      await HiveService.cache.put('pundit_arsenal', 'teks analisis');

      expect(HiveService.cache.get('pundit_chat_arsenal'), isNotNull);

      await PunditRepository.clearCache();

      expect(HiveService.cache.get('pundit_chat_arsenal'), isNull);
      expect(HiveService.cache.get('pundit_arsenal'), isNull);
    });
  });
}
