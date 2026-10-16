import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';

/// B4: server menghitung ulang hash blok dengan `JSON.stringify` atas data yang
/// diterimanya. Bentuk JSON harus sama di kedua sisi, termasuk untuk angka.
void main() {
  group('Block.canonicalDataJson', () {
    test('double bulat diserialisasi tanpa .0 seperti di JavaScript', () {
      // Dart jsonEncode(1500.0) = "1500.0", Node JSON.stringify(1500) = "1500".
      expect(Block.canonicalDataJson({'distance_m': 1500.0}),
          '{"distance_m":1500}');
    });

    test('double pecahan tetap utuh', () {
      expect(Block.canonicalDataJson({'distance_m': 1500.5}),
          '{"distance_m":1500.5}');
    });

    test('int tidak berubah dan key diurutkan menaik', () {
      // Urutan key di-normalisasi (ordinal ascending) supaya sama dengan jsonb
      // Supabase dan JSON.stringify dengan key terurut di sisi server.
      expect(Block.canonicalDataJson({'score': 3, 'goals': 2}),
          '{"goals":2,"score":3}');
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

  group('canonicalDataJson tidak bergantung urutan key', () {
    test('map dua key sama walau urutan insert berbeda', () {
      expect(Block.canonicalDataJson({'b': 1, 'a': 2}),
          Block.canonicalDataJson({'a': 2, 'b': 1}));
      expect(Block.canonicalDataJson({'b': 1, 'a': 2}), '{"a":2,"b":1}');
    });

    test('map bersarang dan map di dalam list ikut diurutkan', () {
      expect(
        Block.canonicalDataJson({
          'b': {
            'z': 1,
            'a': {'n': 2, 'm': 3},
          },
          'a': [
            {'y': 4, 'x': 5},
            6.0,
          ],
        }),
        '{"a":[{"x":5,"y":4},6],"b":{"a":{"m":3,"n":2},"z":1}}',
      );
      // Nilai identik, urutan insert dibalik -> teks kanonik sama.
      expect(
        Block.canonicalDataJson({
          'a': [
            {'x': 5, 'y': 4},
            6,
          ],
          'b': {
            'a': {
              'm': 3,
              'n': 2,
            },
            'z': 1,
          },
        }),
        '{"a":[{"x":5,"y":4},6],"b":{"a":{"m":3,"n":2},"z":1}}',
      );
    });
  });

  group('putaran jsonb (blok tetap valid setelah key diurutkan ulang)', () {
    Block withData(Block b, Map<String, dynamic> data) => Block(
          index: b.index,
          timestamp: b.timestamp,
          type: b.type,
          data: data,
          owner: b.owner,
          prevHash: b.prevHash,
          nonce: b.nonce,
          hash: b.hash,
        );

    test('blok mined dengan multi-key data tetap valid setelah round-trip', () {
      final mined = Blockchain.mine(
        index: 0,
        timestamp: 1,
        type: 'stamp',
        data: const {
          'stadium': 'X',
          'distance_m': 1500.0,
          'gps_verified': true,
          'club': 'arsenal',
        },
        owner: 'me',
        prevHash: Blockchain.genesisPrevHash,
      );
      // Simulasi jsonb: key terurut balik (urutan jsonb), double bulat jadi int.
      final roundTripped = withData(mined, const {
        'club': 'arsenal',
        'gps_verified': true,
        'distance_m': 1500,
        'stadium': 'X',
      });
      expect(Blockchain.isValid([roundTripped]), isTrue);
    });

    test('rantai 3 blok dengan semua data diurutkan ulang tetap valid', () {
      final g = Blockchain.genesis();
      final b1 = Blockchain.next([g], 'stamp', {'b': 2, 'a': 1.0}, 'me');
      final b2 = Blockchain.next([g, b1], 'stamp', {'z': 9, 'y': 8.5}, 'me');
      final reordered = [
        withData(g, const {}),
        withData(b1, const {'a': 1, 'b': 2}),
        withData(b2, const {'y': 8.5, 'z': 9}),
      ];
      expect(Blockchain.isValid(reordered), isTrue);
      // Remote yang lebih panjang (data diurutkan ulang) masih boleh diadopsi.
      expect(Blockchain.canAdoptRemote([g, b1], reordered), isTrue);
    });
  });
}
