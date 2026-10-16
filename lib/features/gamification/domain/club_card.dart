import '../data/blockchain.dart';

/// Tingkat kelangkaan kartu klub.
enum CardRarity { common, rare, epic, legendary }

/// Kartu klub yang diturunkan secara deterministik dari satu blok rantai.
class ClubCard {
  const ClubCard({
    required this.clubKey,
    required this.rarity,
    required this.source,
    required this.blockIndex,
    required this.blockHash,
    required this.earnedAt,
    this.owner = '',
  });

  final String clubKey;
  final CardRarity rarity;
  final String source;
  final int blockIndex;
  final String blockHash;
  final DateTime earnedAt;
  final String owner;
}

/// Rarity dari 8 karakter hex pertama hash, di-mod 100:
/// 0-59 common, 60-84 rare, 85-95 epic, 96-99 legendary.
CardRarity rarityFromHash(String hash) {
  final value = int.parse(hash.substring(0, 8), radix: 16) % 100;
  if (value <= 59) return CardRarity.common;
  if (value <= 84) return CardRarity.rare;
  if (value <= 95) return CardRarity.epic;
  return CardRarity.legendary;
}

/// Klub dari karakter hex 8..16 hash, di-mod jumlah klub.
String clubKeyFromHash(String hash, List<String> clubKeys) {
  final value = int.parse(hash.substring(8, 16), radix: 16) % clubKeys.length;
  return clubKeys[value];
}

/// Turunkan kartu dari sebuah blok. Hanya blok bertipe `card` yang menghasilkan
/// kartu. Klub dan rarity dihitung murni dari [Block.hash] dan tidak pernah
/// dibaca dari field tersimpan, sehingga mengubah isi data tidak memalsukan kartu.
ClubCard? cardFromBlock(Block b, List<String> clubKeys) {
  if (b.type != 'card') return null;
  if (clubKeys.isEmpty) return null;
  return ClubCard(
    clubKey: clubKeyFromHash(b.hash, clubKeys),
    rarity: rarityFromHash(b.hash),
    source: b.data['source']?.toString() ?? '',
    blockIndex: b.index,
    blockHash: b.hash,
    earnedAt: DateTime.fromMillisecondsSinceEpoch(b.timestamp, isUtc: true),
    owner: b.owner,
  );
}
