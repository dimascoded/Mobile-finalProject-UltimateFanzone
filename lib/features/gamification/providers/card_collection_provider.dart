import 'package:flutter_riverpod/flutter_riverpod.dart';

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
