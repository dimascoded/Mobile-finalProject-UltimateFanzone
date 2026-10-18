import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';
import 'package:ultimate_fanzone/features/gamification/providers/card_collection_provider.dart';

PlClub club(String key, String name) => PlClub(
      key: key,
      name: name,
      shortName: name,
      tla: key.substring(0, 3).toUpperCase(),
      city: 'Kota',
      stadium: 'Stadion $name',
      lat: 0,
      lng: 0,
      color: 0xFFEF0107,
      aliases: [name],
    );

ClubCard card(String clubKey, CardRarity rarity, int blockIndex) => ClubCard(
      clubKey: clubKey,
      rarity: rarity,
      source: 'penalty',
      blockIndex: blockIndex,
      blockHash: 'abcdef0123456789abcdef',
      earnedAt: DateTime(2026, 1, blockIndex),
    );

final _clubs = <PlClub>[
  club('arsenal', 'Arsenal'),
  club('chelsea', 'Chelsea'),
  club('liverpool', 'Liverpool'),
  club('everton', 'Everton'),
  club('fulham', 'Fulham'),
];

ProviderContainer _container(List<ClubCard> cards) {
  final container = ProviderContainer(
    overrides: [
      clubsProvider.overrideWith((ref) async => _clubs),
      cardCollectionProvider.overrideWithValue(cards),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('collectionEntriesProvider groups by (clubKey, rarity)', () {
    final container = _container([
      card('arsenal', CardRarity.common, 1),
      card('arsenal', CardRarity.common, 2),
      card('arsenal', CardRarity.epic, 3),
      card('chelsea', CardRarity.rare, 4),
    ]);

    final entries = container.read(collectionEntriesProvider);

    expect(entries.length, 3);
    expect(entries[0].rarity, CardRarity.epic);
    expect(entries[1].rarity, CardRarity.rare);
    expect(entries[2].rarity, CardRarity.common);

    final arsenalCommon = entries.firstWhere(
      (e) => e.clubKey == 'arsenal' && e.rarity == CardRarity.common,
    );
    expect(arsenalCommon.count, 2);
    // Terbaru lebih dulu.
    expect(arsenalCommon.newest.blockIndex, 2);
  });

  test('collectionProgressProvider menghitung klub dan kartu', () async {
    final container = _container([
      card('arsenal', CardRarity.common, 1),
      card('arsenal', CardRarity.common, 2),
      card('arsenal', CardRarity.epic, 3),
      card('chelsea', CardRarity.rare, 4),
    ]);
    await container.read(clubsProvider.future);

    final progress = container.read(collectionProgressProvider);

    expect(progress.clubsOwned, 2);
    expect(progress.totalCards, 4);
    expect(progress.entries, 3);
    expect(progress.clubsTotal, 5);
  });
}
