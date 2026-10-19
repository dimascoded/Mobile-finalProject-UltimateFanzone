import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';

FootballMatch _match({
  required int id,
  required String status,
  required DateTime kickoff,
  int? homeScore,
  int? awayScore,
}) =>
    FootballMatch(
      id: id,
      kickoffUtc: kickoff,
      status: status,
      matchday: 1,
      homeName: 'Team $id',
      awayName: 'Rival $id',
      homeShort: 'T$id',
      awayShort: 'R$id',
      homeScore: homeScore,
      awayScore: awayScore,
    );

void main() {
  test('MatchFilter.upcoming excludes awaitingResult', () async {
    final now = DateTime.now().toUtc();
    final matches = <FootballMatch>[
      _match(id: 1, status: 'TIMED', kickoff: now.add(const Duration(hours: 2))),
      _match(id: 2, status: 'TIMED', kickoff: now.subtract(const Duration(minutes: 10))),
      _match(id: 3, status: 'TIMED', kickoff: now.subtract(const Duration(hours: 4))),
      _match(
        id: 4,
        status: 'FINISHED',
        kickoff: now.subtract(const Duration(days: 1)),
        homeScore: 2,
        awayScore: 1,
      ),
    ];

    final container = ProviderContainer(overrides: [
      matchesProvider.overrideWith((ref) async =>
          FootballResult<List<FootballMatch>>(matches, DataSource.live, now)),
      favoriteClubProvider.overrideWithValue(null),
    ]);
    addTearDown(container.dispose);
    await container.read(matchesProvider.future);

    final sub = container.listen(matchFilterProvider, (_, __) {});
    addTearDown(sub.close);

    List<int> ids() =>
        container.read(filteredMatchesProvider).valueOrNull!.data
            .map((m) => m.id)
            .toList();

    expect(ids(), contains(1));
    expect(ids(), contains(2));
    expect(ids(), isNot(contains(3)));
    expect(ids(), isNot(contains(4)));

    container.read(matchFilterProvider.notifier).state = MatchFilter.finished;
    expect(ids(), contains(3));
    expect(ids(), contains(4));
    expect(ids(), isNot(contains(1)));
  });
}
