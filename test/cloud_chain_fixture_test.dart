import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/sync/data/chain_reconcile.dart';

/// Empat baris `passport_chain_blocks` persis seperti dikembalikan PostgREST:
/// kunci snake_case, angka sebagai angka. Hash sudah diverifikasi independen
/// (sha256 dengan JSON kanonik key-terurut) dan semuanya cocok.
const List<Map<String, dynamic>> cloudRows = [
  {
    'idx': 0,
    'timestamp': 0,
    'type': 'genesis',
    'data': <String, dynamic>{},
    'owner': 'system',
    'prev_hash':
        '0000000000000000000000000000000000000000000000000000000000000000',
    'nonce': 3220,
    'hash': '000005fe48870c505f6377a87bb702709a735e65f412f0cf0b6ce7dc4c41ae45',
  },
  {
    'idx': 1,
    'timestamp': 1792139666348,
    'type': 'stamp',
    'data': <String, dynamic>{
      'club': 'man_united',
      'stadium': 'Old Trafford',
      'distance_m': 0,
      'gps_verified': false,
    },
    'owner': '0x0de33957e86705091dB9a9335D67c11bB6ecE7c0',
    'prev_hash':
        '000005fe48870c505f6377a87bb702709a735e65f412f0cf0b6ce7dc4c41ae45',
    'nonce': 5818,
    'hash': '000e95a5907efa42e2452be74e3e0f9ec337930bf82da61cc3ccbeb5d917fcd3',
  },
  {
    'idx': 2,
    'timestamp': 1792139766542,
    'type': 'achievement',
    'data': <String, dynamic>{
      'game': 'Penalty Shootout',
      'hash': '20fcaa4ef76d73ca75361ce91a6ac137e69a13babdacd8f48c50fde5c3572880',
      'goals': 2,
      'score': 200,
      'attempts': 5,
    },
    'owner': '0x0de33957e86705091dB9a9335D67c11bB6ecE7c0',
    'prev_hash':
        '000e95a5907efa42e2452be74e3e0f9ec337930bf82da61cc3ccbeb5d917fcd3',
    'nonce': 472,
    'hash': '0008bf769fc6a45752915e2b6416cc3c93612aa5ce6481a1084989b8d60a9653',
  },
  {
    'idx': 3,
    'timestamp': 1792139766730,
    'type': 'card',
    'data': <String, dynamic>{
      'ref': 'penalty:2026-10-16',
      'source': 'penalty',
    },
    'owner': '0x0de33957e86705091dB9a9335D67c11bB6ecE7c0',
    'prev_hash':
        '0008bf769fc6a45752915e2b6416cc3c93612aa5ce6481a1084989b8d60a9653',
    'nonce': 10965,
    'hash': '0002ef67b90643cd11fd8cb3bf75779855042c479baef6e5713708b9517ed6f9',
  },
];

void main() {
  // Jalur produksi yang sama dengan _syncSupabase: blockRowToJson lalu
  // Block.fromJson (SyncRepository.parseChain).
  final blocks = [
    for (final row in cloudRows) Block.fromJson(blockRowToJson(row)),
  ];

  test('(a) pemetaan baris cloud mempertahankan semua field', () {
    for (var i = 0; i < cloudRows.length; i++) {
      final row = cloudRows[i];
      final b = blocks[i];
      expect(b.index, row['idx'], reason: 'blok #$i: index');
      expect(b.timestamp, row['timestamp'], reason: 'blok #$i: timestamp');
      expect(b.type, row['type'], reason: 'blok #$i: type');
      expect(b.data, row['data'], reason: 'blok #$i: data');
      expect(b.owner, row['owner'], reason: 'blok #$i: owner');
      expect(b.prevHash, row['prev_hash'], reason: 'blok #$i: prevHash');
      expect(b.nonce, row['nonce'], reason: 'blok #$i: nonce');
      expect(b.hash, row['hash'], reason: 'blok #$i: hash');
    }
  });

  test('(b) Blockchain.isValid atas blok hasil pemetaan', () {
    expect(Blockchain.isValid(blocks), isTrue);
  });

  test('(c) reconcileChain([genesis], blocks) -> adoptRemote', () {
    expect(
      reconcileChain([Blockchain.genesis()], blocks),
      ChainOutcome.adoptRemote,
    );
  });

  test('(d) reconcileChain(blocks, blocks) -> inSync', () {
    expect(reconcileChain(blocks, blocks), ChainOutcome.inSync);
  });

  // Regresi: `_selectAll(orderBy: 'idx')` memakai `.order()` PostgREST yang
  // bawaannya menurun, jadi baris cloud sebenarnya datang idx besar dulu.
  // Tanpa pengurutan menaik, rantai yang sebenarnya utuh ini ditolak dan
  // aplikasi melempar "Riwayat di cloud tidak valid."
  group('urutan produksi (DESC)', () {
    final productionRows = cloudRows.reversed.toList();
    final productionBlocks = [
      for (final row in productionRows) Block.fromJson(blockRowToJson(row)),
    ];

    test('sebelum diurutkan, rantai sah tampak tidak valid', () {
      expect(Blockchain.isValid(productionBlocks), isFalse);
      expect(
        () => reconcileChain([Blockchain.genesis()], productionBlocks),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Riwayat di cloud tidak valid (catatan #0).',
        )),
      );
    });

    test('setelah sortBlockRowsByIndex, rantai valid dan bisa direkonsiliasi',
        () {
      final sorted = [
        for (final row in sortBlockRowsByIndex(productionRows))
          Block.fromJson(blockRowToJson(row)),
      ];
      expect(firstInvalidIndex(sorted), isNull);
      expect(Blockchain.isValid(sorted), isTrue);
      expect(
        reconcileChain([Blockchain.genesis()], sorted),
        ChainOutcome.adoptRemote,
      );
      expect(reconcileChain(sorted, sorted), ChainOutcome.inSync);
    });

    test('sortBlockRowsByIndex idempoten dan tidak mengubah isi baris', () {
      final once = sortBlockRowsByIndex(productionRows);
      expect([for (final r in once) r['idx']], [0, 1, 2, 3]);
      expect(sortBlockRowsByIndex(once), once);
      expect(sortBlockRowsByIndex(cloudRows), cloudRows);
    });
  });
}
