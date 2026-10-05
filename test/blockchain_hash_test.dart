import 'package:flutter_test/flutter_test.dart';
import 'package:premiere_league_fan_assistant/features/gamification/data/blockchain.dart';

/// B4: server menghitung ulang hash blok dengan `JSON.stringify` atas data yang
/// diterimanya. Bentuk JSON harus sama di kedua sisi, termasuk untuk angka.
void main() {
  group('Block.canonicalDataJson', () {
    test('double bulat diserialisasi tanpa .0 seperti di JavaScript', () {
      // Dart jsonEncode(1500.0) = "1500.0", Node JSON.stringify(1500) = "1500".
      expect(Block.canonicalDataJson({'distance_m': 1500.0}), '{"distance_m":1500}');
    });

    test('double pecahan tetap utuh', () {
      expect(Block.canonicalDataJson({'distance_m': 1500.5}),
          '{"distance_m":1500.5}');
    });

    test('int tidak berubah dan urutan key dipertahankan', () {
      expect(Block.canonicalDataJson({'score': 3, 'goals': 2}),
          '{"score":3,"goals":2}');
    });

    test('data bersarang ikut dinormalkan', () {
      expect(
        Block.canonicalDataJson({
          'a': 1.0,
          'b': [2.0, 3.5, 'x'],
          'c': {'d': 4.0},
        }),
        '{"a":1,"b":[2,3.5,"x"],"c":{"d":4}}',
      );
    });
  });

  group('Block.computeHash', () {
    test('hash sama untuk data dengan 1500 dan 1500.0', () {
      String hashFor(Object distance) => Block.computeHash(
            index: 1,
            timestamp: 2,
            type: 'stamp',
            data: {'distance_m': distance},
            owner: '0xabc',
            prevHash: '0' * 64,
            nonce: 7,
          );
      expect(hashFor(1500), hashFor(1500.0));
    });

    test('hash tetap memenuhi proof-of-work', () {
      final block = Blockchain.mine(
        index: 0,
        timestamp: 1,
        type: 'genesis',
        data: const {},
        owner: 'system',
        prevHash: Blockchain.genesisPrevHash,
      );
      expect(block.hash.startsWith('000'), isTrue);
      expect(
        Block.computeHash(
          index: block.index,
          timestamp: block.timestamp,
          type: block.type,
          data: block.data,
          owner: block.owner,
          prevHash: block.prevHash,
          nonce: block.nonce,
        ),
        block.hash,
      );
    });

    test('perubahan isi data mengubah hash', () {
      String hashFor(Map<String, dynamic> data) => Block.computeHash(
            index: 1,
            timestamp: 2,
            type: 'stamp',
            data: data,
            owner: '0xabc',
            prevHash: '0' * 64,
            nonce: 7,
          );
      expect(hashFor({'club': 'arsenal'}), isNot(hashFor({'club': 'chelsea'})));
    });
  });
}
