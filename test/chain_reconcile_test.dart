import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/sync/data/chain_reconcile.dart';

Block stamp(int index, int timestamp, String stadium, String prevHash) =>
    Blockchain.mine(
      index: index,
      timestamp: timestamp,
      type: 'stamp',
      data: {'stadium': stadium},
      owner: 'me',
      prevHash: prevHash,
    );

void main() {
  final genesis = Blockchain.genesis();
  final b1 = stamp(1, 1, 'A', genesis.hash);
  final b2 = stamp(2, 2, 'B', b1.hash);
  final b3 = stamp(3, 3, 'C', b2.hash);

  group('reconcileChain', () {
    test('cloud kosong -> pushLocal', () {
      expect(
        reconcileChain([genesis, b1], const []),
        ChainOutcome.pushLocal,
      );
    });

    test('identik -> inSync', () {
      expect(
        reconcileChain([genesis, b1, b2], [genesis, b1, b2]),
        ChainOutcome.inSync,
      );
    });

    test('cloud memperpanjang awalan -> adoptRemote', () {
      expect(
        reconcileChain([genesis, b1], [genesis, b1, b2]),
        ChainOutcome.adoptRemote,
      );
    });

    test('lokal memperpanjang awalan -> pushLocal', () {
      expect(
        reconcileChain([genesis, b1, b2], [genesis, b1]),
        ChainOutcome.pushLocal,
      );
    });

    test('genesis sama, blok #1 berbeda -> adoptRemote dan hitung yang dibuang',
        () {
      final localB1 = stamp(1, 1, 'LOCAL', genesis.hash);
      final remoteB1 = stamp(1, 1, 'REMOTE', genesis.hash);
      final remoteB2 = stamp(2, 2, 'REMOTE2', remoteB1.hash);
      final local = [genesis, localB1];
      final remote = [genesis, remoteB1, remoteB2];

      expect(reconcileChain(local, remote), ChainOutcome.adoptRemote);
      expect(droppedLocalBlocks(local, remote), local.length - 1);
    });

    test('genesis berbeda -> melempar StateError', () {
      final otherGenesis = Blockchain.mine(
        index: 0,
        timestamp: 0,
        type: 'genesis',
        data: const {'v': 2},
        owner: 'system',
        prevHash: Blockchain.genesisPrevHash,
      );
      expect(
        () => reconcileChain([genesis], [otherGenesis]),
        throwsStateError,
      );
    });

    test('lokal hanya genesis vs cloud 3 blok -> adoptRemote', () {
      expect(
        reconcileChain([genesis], [genesis, b1, b2, b3]),
        ChainOutcome.adoptRemote,
      );
    });
  });

  group('firstInvalidIndex', () {
    test('rantai utuh -> null', () {
      expect(firstInvalidIndex([genesis, b1, b2, b3]), isNull);
    });

    test('rantai kosong -> 0 (isValid juga menolaknya)', () {
      expect(firstInvalidIndex(const []), 0);
    });

    test('rantai terbalik (idx menurun) -> 0', () {
      expect(firstInvalidIndex([b3, b2, b1, genesis]), 0);
    });

    test('hash di indeks 2 diretas -> 2', () {
      final tampered = Block(
        index: 2,
        timestamp: 2,
        type: 'stamp',
        data: const {'stadium': 'B'},
        owner: 'me',
        prevHash: b1.hash,
        nonce: b2.nonce,
        hash: 'f' * 64,
      );
      expect(firstInvalidIndex([genesis, b1, tampered]), 2);
      expect(Blockchain.isValid([genesis, b1, tampered]), isFalse);
    });

    test('prevHash terputus di indeks 1 -> 1', () {
      final orphan = stamp(1, 1, 'X', 'f' * 64);
      expect(firstInvalidIndex([genesis, orphan]), 1);
      expect(Blockchain.isValid([genesis, orphan]), isFalse);
    });
  });

  group('pesan galat reconcileChain', () {
    test('blok rusak menyebut urutan catatannya', () {
      final tampered = Block(
        index: 2,
        timestamp: 2,
        type: 'stamp',
        data: const {'stadium': 'B'},
        owner: 'me',
        prevHash: b1.hash,
        nonce: b2.nonce,
        hash: 'f' * 64,
      );
      expect(
        () => reconcileChain([genesis], [genesis, b1, tampered]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Riwayat di cloud tidak valid (catatan #2).',
        )),
      );
    });

    test('genesis beda menyebut berbeda genesis', () {
      final otherGenesis = Blockchain.mine(
        index: 0,
        timestamp: 0,
        type: 'genesis',
        data: const {'v': 2},
        owner: 'system',
        prevHash: Blockchain.genesisPrevHash,
      );
      expect(
        () => reconcileChain([genesis], [otherGenesis]),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('berbeda genesis'),
        )),
      );
    });
  });

  test('baris cloud dengan angka jsonb int round-trip dan tetap valid', () {
    final block = Blockchain.mine(
      index: 0,
      timestamp: 1700000000000,
      type: 'stamp',
      data: const {'distance_m': 1500.0},
      owner: 'me',
      prevHash: Blockchain.genesisPrevHash,
    );
    final row = <String, dynamic>{
      'idx': 0,
      'timestamp': 1700000000000,
      'type': 'stamp',
      'data': <String, dynamic>{'distance_m': 1500},
      'owner': 'me',
      'prev_hash': Blockchain.genesisPrevHash,
      'nonce': block.nonce,
      'hash': block.hash,
    };

    final parsed = Block.fromJson(blockRowToJson(row));
    expect(parsed.data['distance_m'], 1500);
    expect(Blockchain.isValid([parsed]), isTrue);
  });
}
