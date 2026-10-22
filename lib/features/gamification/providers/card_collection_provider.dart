import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../domain/club_card.dart';
import 'gamification_providers.dart';

/// Katalog klub (hanya key) dari aset lokal. Kosong selama aset belum termuat.
///
/// Provider turunan dari [clubsProvider]: hanya menyimpan `key` setiap
/// [PlClub], karena itu yang dipakai sebagai kunci kartu dan perhitungan
/// rarity. Tanpa efek samping.
final clubKeysProvider = Provider<List<String>>((ref) {
  final clubs = ref.watch(clubsProvider).valueOrNull;
  return clubs == null ? const <String>[] : [for (final c in clubs) c.key];
});

/// Semua kartu klub yang bisa diturunkan dari rantai, terbaru lebih dulu.
/// Tidak memicu mint; murni membaca state rantai yang ada.
///
/// Provider turunan dari [chainProvider] dan [clubKeysProvider]: setiap blok
/// bertipe `card` dipetakan ke [ClubCard] lewat [cardFromBlock], di mana klub
/// dan rarity dihitung dari hash blok sehingga tidak bisa dimanipulasi.
/// Kartu diurutkan menurut indeks blok menaik (terbaru di posisi paling
/// awal). Tanpa efek samping.
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
///
/// Provider turunan dari [cardCollectionProvider]: setiap rarity
/// ([CardRarity.values]) selalu ada di peta meski nilainya 0.
/// Tanpa efek samping.
final cardRarityCountsProvider = Provider<Map<CardRarity, int>>((ref) {
  final counts = {for (final r in CardRarity.values) r: 0};
  for (final card in ref.watch(cardCollectionProvider)) {
    counts[card.rarity] = counts[card.rarity]! + 1;
  }
  return counts;
});

/// Klub berbeda yang sudah dimiliki (satu atau lebih kartu).
///
/// Provider turunan dari [cardCollectionProvider]: hanya mengembalikan
/// kunci klub unik, tanpa jumlah kartu per klub. Tanpa efek samping.
final ownedClubsProvider = Provider<Set<String>>(
    (ref) => {for (final c in ref.watch(cardCollectionProvider)) c.clubKey});

/// Entri koleksi untuk setiap pasangan (klub, rarity).
///
/// Dipakai layar koleksi sebagai satu baris tampilan yang memuat daftar kartu,
/// jumlah, dan kartu terbaru (indeks blok tertinggi).
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
///
/// Provider turunan dari [cardCollectionProvider] dan [clubsProvider]:
/// kartu dikelompokkan per pasangan (klub, rarity), kartu dalam kelompok
/// diurutkan terbaru dulu, dan kelompok diurutkan menurut rarity (legendary
/// lebih dulu), lalu nama klub (A-Z), lalu blok terbaru. Tanpa efek samping.
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

/// Progress koleksi: jumlah klub yang dimiliki, total klub, jumlah entri
/// grup (klub x rarity), dan total kartu.
typedef CollectionProgress = ({
  int clubsOwned,
  int clubsTotal,
  int entries,
  int totalCards,
});

/// Progress koleksi.
///
/// Provider turunan dari [clubsProvider], [ownedClubsProvider],
/// [collectionEntriesProvider], dan [cardCollectionProvider]; dipakai layar
/// koleksi untuk menampilkan "X dari Y klub" dan total kartu.
/// Tanpa efek samping.
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
