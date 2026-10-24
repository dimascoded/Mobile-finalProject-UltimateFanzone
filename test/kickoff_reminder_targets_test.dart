import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/kickoff_reminder_provider.dart';

void main() {
  const fav = PlClub(
    key: 'ars',
    name: 'Arsenal FC',
    shortName: 'Arsenal',
    tla: 'ARS',
    city: 'London',
    stadium: 'Emirates Stadium',
    lat: 51.5549,
    lng: -0.1084,
    color: 0xFFEF0107,
    aliases: ['arsenal'],
  );
  const rival = PlClub(
    key: 'che',
    name: 'Chelsea FC',
    shortName: 'Chelsea',
    tla: 'CHE',
    city: 'London',
    stadium: 'Stamford Bridge',
    lat: 51.4817,
    lng: -0.1910,
    color: 0xFF034694,
    aliases: ['chelsea'],
  );
  const neutral = PlClub(
    key: 'liv',
    name: 'Liverpool FC',
    shortName: 'Liverpool',
    tla: 'LIV',
    city: 'Liverpool',
    stadium: 'Anfield',
    lat: 53.4308,
    lng: -2.9608,
    color: 0xFFC8102E,
    aliases: ['liverpool'],
  );

  final now = DateTime.utc(2026, 10, 1, 12);

  FootballMatch match(
    int id,
    Duration offset, {
    bool withFavorite = false,
    String status = 'TIMED',
    DateTime? base,
  }) {
    final home = withFavorite ? fav : neutral;
    final away = withFavorite ? rival : rival;
    return FootballMatch(
      id: id,
      kickoffUtc: (base ?? now).add(offset),
      status: status,
      matchday: id,
      homeName: home.name,
      awayName: away.name,
      homeShort: home.shortName,
      awayShort: away.shortName,
      homeTla: home.tla,
      awayTla: away.tla,
    );
  }

  group('kickoffReminderTargets', () {
    test('tanpa tim favorit memakai 10 laga terdekat seluruh liga', () {
      final data = [
        for (var i = 1; i <= 15; i++) match(i, Duration(days: i)),
      ];
      final targets = kickoffReminderTargets(data, null, now: now);
      expect(targets.map((m) => m.id), [for (var i = 1; i <= 10; i++) i]);
    });

    test('laga favorit yang jauh di masa depan tetap disertakan', () {
      final data = [
        for (var i = 1; i <= 12; i++) match(i, Duration(days: i)),
        match(99, const Duration(days: 50), withFavorite: true),
      ];
      final targets = kickoffReminderTargets(data, fav, now: now);
      expect(targets.length, 11);
      expect(targets.map((m) => m.id), contains(99));
      expect(targets.first.id, 1);
      expect(targets.last.id, 99);
    });

    test('laga yang sama tidak muncul dua kali', () {
      final data = [
        for (var i = 1; i <= 12; i++)
          match(i, Duration(days: i), withFavorite: i == 5),
      ];
      final targets = kickoffReminderTargets(data, fav, now: now);
      expect(targets.length, 10);
      expect(targets.where((m) => m.id == 5).length, 1);
    });

    test('hanya laga berstatus upcoming yang dipakai', () {
      final data = [
        match(1, const Duration(days: 1)),
        match(2, const Duration(days: -10), status: 'FINISHED'),
        match(3, const Duration(hours: -4)),
      ];
      final targets = kickoffReminderTargets(data, null, now: now);
      expect(targets.map((m) => m.id), [1]);
    });

    test('hasil terurut berdasarkan kickoff', () {
      final data = [
        match(302, const Duration(days: 3)),
        match(101, const Duration(days: 1)),
        match(202, const Duration(days: 2)),
      ];
      final targets = kickoffReminderTargets(data, null, now: now);
      expect(targets.map((m) => m.id), [101, 202, 302]);
    });

    test('batas 54 notifikasi memangkas laga non-favorit lebih dulu', () {
      final data = [
        for (var i = 1; i <= 20; i++)
          match(i, Duration(days: i), withFavorite: i >= 11),
      ];
      final targets =
          kickoffReminderTargets(data, fav, now: now, leadCount: 3);
      expect(targets.length, 18);
      expect(targets.map((m) => m.id), containsAll([for (var i = 11; i <= 20; i++) i]));
      expect(targets.map((m) => m.id), isNot(contains(9)));
      expect(targets.map((m) => m.id), isNot(contains(10)));
      expect(targets.length * 3, lessThanOrEqualTo(maxKickoffNotifications));
    });

    test('leadCount 1 dan 3 menghasilkan jumlah target berbeda', () {
      final data = [
        for (var i = 1; i <= 20; i++)
          match(i, Duration(days: i), withFavorite: i >= 11),
      ];
      final oneLead = kickoffReminderTargets(data, fav, now: now);
      final threeLeads =
          kickoffReminderTargets(data, fav, now: now, leadCount: 3);
      expect(oneLead.length, 20);
      expect(threeLeads.length, 18);
    });

    test('reminderTargets tetap hanya laga tim favorit', () {
      final realNow = DateTime.now().toUtc();
      final data = [
        for (var i = 1; i <= 5; i++)
          match(i, Duration(days: i), base: realNow),
        match(6, const Duration(days: 6),
            withFavorite: true, base: realNow),
      ];
      expect(reminderTargets(data, fav).map((m) => m.id), [6]);
      expect(reminderTargets(data, null), isEmpty);
    });
  });
}
