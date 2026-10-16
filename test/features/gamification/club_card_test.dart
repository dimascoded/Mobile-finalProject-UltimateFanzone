import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';

/// Hash 64 karakter: 8 hex pertama = rarity seed, 8 berikutnya = club seed.
String hashWith({required int raritySeed, required int clubSeed}) {
  final rarity = raritySeed.toRadixString(16).padLeft(8, '0');
  final club = clubSeed.toRadixString(16).padLeft(8, '0');
  return '$rarity$club${'0' * 48}';
}

Block blockWith({
  required String hash,
  String type = 'card',
  String source = 'pack',
  int index = 1,
  int timestamp = 1700000000000,
}) =>
    Block(
      index: index,
      timestamp: timestamp,
      type: type,
      data: {'source': source},
      owner: 'owner',
      prevHash: '0' * 64,
      nonce: 0,
      hash: hash,
    );

const clubKeys = ['arsenal', 'chelsea', 'liverpool', 'everton'];

void main() {
  group('rarityFromHash', () {
    test('batas tiap rarity tepat di 59/60, 84/85, 95/96', () {
      final cases = <int, CardRarity>{
        0: CardRarity.common,
        59: CardRarity.common,
        60: CardRarity.rare,
        84: CardRarity.rare,
        85: CardRarity.epic,
        95: CardRarity.epic,
        96: CardRarity.legendary,
        99: CardRarity.legendary,
        100: CardRarity.common, // mod 100
        199: CardRarity.legendary,
      };
      cases.forEach((seed, expected) {
        expect(rarityFromHash(hashWith(raritySeed: seed, clubSeed: 0)),
            expected,
            reason: 'seed $seed');
      });
    });
  });

  group('clubKeyFromHash', () {
    test('memakai segmen hex 8..16 dan membungkus dengan panjang katalog', () {
      expect(clubKeyFromHash(hashWith(raritySeed: 0, clubSeed: 0), clubKeys),
          'arsenal');
      expect(clubKeyFromHash(hashWith(raritySeed: 0, clubSeed: 7), clubKeys),
          'everton'); // 7 % 4 == 3
      expect(clubKeyFromHash(hashWith(raritySeed: 0, clubSeed: 9), clubKeys),
          'chelsea'); // 9 % 4 == 1
    });
  });

  group('cardFromBlock', () {
    test('hash yang sama selalu menghasilkan kartu yang sama', () {
      final hash = hashWith(raritySeed: 12, clubSeed: 12345);
      final first = cardFromBlock(blockWith(hash: hash, index: 3), clubKeys)!;
      final second =
          cardFromBlock(blockWith(hash: hash, index: 3), clubKeys)!;

      expect(first.clubKey, second.clubKey);
      expect(first.rarity, second.rarity);
      expect(first.blockHash, hash);
      expect(first.blockIndex, 3);
      expect(first.rarity, rarityFromHash(hash));
      expect(first.clubKey, clubKeyFromHash(hash, clubKeys));
    });

    test("blok selain tipe 'card' mengembalikan null", () {
      final hash = hashWith(raritySeed: 96, clubSeed: 0);
      expect(cardFromBlock(blockWith(hash: hash, type: 'stamp'), clubKeys),
          isNull);
      expect(cardFromBlock(blockWith(hash: hash, type: 'achievement'), clubKeys),
          isNull);
    });

    test("mengubah b.data['source'] tidak mengubah clubKey maupun rarity", () {
      final hash = hashWith(raritySeed: 200, clubSeed: 54321);
      final original = cardFromBlock(blockWith(hash: hash, source: 'pack'), clubKeys)!;
      final tampered = cardFromBlock(blockWith(hash: hash, source: 'cheat'), clubKeys)!;

      expect(tampered.clubKey, original.clubKey);
      expect(tampered.rarity, original.rarity);
      expect(original.source, 'pack');
      expect(tampered.source, 'cheat');
    });
  });

  test('distribusi 5000 hash sha256 dalam Â±3 poin dari 60/25/11/4', () {
    const total = 5000;
    const tolerance = 0.03;
    final counts = {for (final r in CardRarity.values) r: 0};
    for (var i = 0; i < total; i++) {
      final hash = sha256.convert(utf8.encode('club-card-$i')).toString();
      final rarity = rarityFromHash(hash);
      counts[rarity] = counts[rarity]! + 1;
    }

    const expected = {
      CardRarity.common: 0.60,
      CardRarity.rare: 0.25,
      CardRarity.epic: 0.11,
      CardRarity.legendary: 0.04,
    };
    expected.forEach((rarity, share) {
      final actual = counts[rarity]! / total;
      expect((actual - share).abs() <= tolerance, isTrue,
          reason: '${rarity.name}: ${(actual * 100).toStringAsFixed(2)}% '
              'vs ${(share * 100).toStringAsFixed(0)}%');
    });
  });
}
