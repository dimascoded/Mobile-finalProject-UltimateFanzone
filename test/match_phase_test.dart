import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';

FootballMatch _match({
  required String status,
  required DateTime kickoffUtc,
  int? homeScore,
  int? awayScore,
}) =>
    FootballMatch(
      id: 1,
      kickoffUtc: kickoffUtc,
      status: status,
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
      homeScore: homeScore,
      awayScore: awayScore,
    );

void main() {
  final now = DateTime.utc(2026, 3, 1, 12);

  test('phaseAt: status yang dibatalkan', () {
    for (final status in ['POSTPONED', 'CANCELLED', 'SUSPENDED']) {
      final m = _match(status: status, kickoffUtc: now.add(const Duration(hours: 1)));
      expect(m.phaseAt(now), MatchPhase.cancelled, reason: status);
    }
  });

  test('phaseAt: status selesai termasuk AWARDED', () {
    expect(
      _match(status: 'FINISHED', kickoffUtc: now.subtract(const Duration(days: 1)))
          .phaseAt(now),
      MatchPhase.finished,
    );
    expect(
      _match(status: 'AWARDED', kickoffUtc: now.subtract(const Duration(days: 1)))
          .phaseAt(now),
      MatchPhase.finished,
    );
  });

  test('phaseAt: status live eksplisit', () {
    for (final status in ['IN_PLAY', 'PAUSED', 'LIVE']) {
      final m = _match(
          status: status, kickoffUtc: now.subtract(const Duration(minutes: 5)));
      expect(m.phaseAt(now), MatchPhase.live, reason: status);
    }
  });

  test('phaseAt: kickoff 10 menit lalu + TIMED -> live', () {
    final m = _match(
        status: 'TIMED', kickoffUtc: now.subtract(const Duration(minutes: 10)));
    expect(m.phaseAt(now), MatchPhase.live);
  });

  test('phaseAt: tepat di bawah 150 menit masih live', () {
    final m = _match(
        status: 'TIMED',
        kickoffUtc: now.subtract(const Duration(minutes: 149)));
    expect(m.phaseAt(now), MatchPhase.live);
  });

  test('phaseAt: kickoff 4 jam lalu + TIMED -> awaitingResult', () {
    final m = _match(
        status: 'TIMED', kickoffUtc: now.subtract(const Duration(hours: 4)));
    expect(m.phaseAt(now), MatchPhase.awaitingResult);
  });

  test('phaseAt: tepat 150 menit -> awaitingResult', () {
    final m = _match(
        status: 'TIMED',
        kickoffUtc: now.subtract(const Duration(minutes: 150)));
    expect(m.phaseAt(now), MatchPhase.awaitingResult);
  });

  test('phaseAt: kickoff di masa depan -> upcoming', () {
    final m = _match(
        status: 'TIMED', kickoffUtc: now.add(const Duration(hours: 2)));
    expect(m.phaseAt(now), MatchPhase.upcoming);
  });

  test('phaseAt: finished menang atas jendela waktu', () {
    final m = _match(
      status: 'FINISHED',
      kickoffUtc: now.subtract(const Duration(minutes: 10)),
      homeScore: 2,
      awayScore: 1,
    );
    expect(m.phaseAt(now), MatchPhase.finished);
  });
}
