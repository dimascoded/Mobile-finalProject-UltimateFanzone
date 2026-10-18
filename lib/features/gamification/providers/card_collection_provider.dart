import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../domain/club_card.dart';
import 'gamification_providers.dart';

/// Katalog klub (hanya key) dari aset lokal. Kosong selama aset belum termuat.
final clubKeysProvider = Provider<List<String>>((ref) {
  final clubs = ref.watch(clubsProvider).valueOrNull;
  return clubs == null ? const <String>[] : [for (final c in clubs) c.key];
});

/// Semua kartu klub yang bisa diturunkan dari rantai, terbaru lebih dulu.
/// Tidak memicu mint; murni membaca state rantai yang ada.
final cardCollectionProvider = Provider<List<ClubCard>>((ref) {
  final clubKeys = ref.watch(clubKeysProvider);
  if (clubKeys.isEmpty) return const <ClubCard>[];
  final cards = <ClubCard>[];
  for (final block in ref.watch(chainProvider)) {
    final card = cardFromBlock(block, clubKeys);
    if (card != null) cards.add(card);
  }
  cards.sort((a, b) => b.blockIndex.compareTo(a.blockIndex));
  return cards;
});

/// Jumlah kartu per rarity.
final cardRarityCountsProvider = Provider<Map<CardRarity, int>>((ref) {
  final counts = {for (final r in CardRarity.values) r: 0};
  for (final card in ref.watch(cardCollectionProvider)) {
    counts[card.rarity] = counts[card.rarity]! + 1;
  }
  return counts;
});

/// Klub berbeda yang sudah dimiliki (satu atau lebih kartu).
final ownedClubsProvider = Provider<Set<String>>(
    (ref) => {for (final c in ref.watch(cardCollectionProvider)) c.clubKey});

/// Entri koleksi untuk setiap pasangan (klub, rarity).
class CollectionEntry {
  CollectionEntry(
      {required this.clubKey, required this.rarity, required this.cards});

  final String clubKey;
  final CardRarity rarity;
  final List<ClubCard> cards;

  int get count => cards.length;
  ClubCard get newest => cards.first;
}

/// Daftar entri koleksi, dikelompokkan berdasarkan (clubKey, rarity).
final collectionEntriesProvider = Provider<List<CollectionEntry>>((ref) {
  final allCards = ref.watch(cardCollectionProvider);
  final clubs = ref.watch(clubsProvider).valueOrNull ?? const <PlClub>[];
  final clubNameByKey = {for (final c in clubs) c.key: c.name};

  final grouped = <String, CollectionEntry>{};
  for (final card in allCards) {
    final key = '${card.clubKey}|${card.rarity.name}';
    grouped.putIfAbsent(
      key,
      () => CollectionEntry(
        clubKey: card.clubKey,
        rarity: card.rarity,
        cards: <ClubCard>[],
      ),
    );
    grouped[key]!.cards.add(card);
  }

  final entries = grouped.values.toList();
  for (final entry in entries) {
    entry.cards.sort((a, b) => b.blockIndex.compareTo(a.blockIndex));
  }

  entries.sort((a, b) {
    if (a.rarity.index != b.rarity.index) {
      return b.rarity.index.compareTo(a.rarity.index);
    }
    final nameA = clubNameByKey[a.clubKey] ?? a.clubKey;
    final nameB = clubNameByKey[b.clubKey] ?? b.clubKey;
    final nameCompare = nameA.compareTo(nameB);
    if (nameCompare != 0) return nameCompare;
    return b.newest.blockIndex.compareTo(a.newest.blockIndex);
  });

  return entries;
});

typedef CollectionProgress = ({
  int clubsOwned,
  int clubsTotal,
  int entries,
  int totalCards,
});

/// Progress koleksi.
final collectionProgressProvider = Provider<CollectionProgress>((ref) {
  final clubs = ref.watch(clubsProvider).valueOrNull ?? const <PlClub>[];
  final ownedClubs = ref.watch(ownedClubsProvider);
  final entries = ref.watch(collectionEntriesProvider);
  final totalCards = ref.watch(cardCollectionProvider).length;
  return (
    clubsOwned: ownedClubs.length,
    clubsTotal: clubs.length,
    entries: entries.length,
    totalCards: totalCards,
  );
});
