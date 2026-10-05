import 'dart:convert';
import '../../../core/utils/crypto_utils.dart';

/// Blockchain sederhana (Dart murni, tanpa dependensi Flutter -> mudah di-unit-test).
/// Tiap blok memuat hash blok sebelumnya + proof-of-work ringan.
class Block {
  const Block({
    required this.index,
    required this.timestamp,
    required this.type,
    required this.data,
    required this.owner,
    required this.prevHash,
    required this.nonce,
    required this.hash,
  });

  final int index, timestamp, nonce;
  final String type, owner, prevHash, hash;
  final Map<String, dynamic> data;

  static String computeHash({
    required int index,
    required int timestamp,
    required String type,
    required Map<String, dynamic> data,
    required String owner,
    required String prevHash,
    required int nonce,
  }) =>
      CryptoUtils.sha256Hash(
          '$index|$timestamp|$type|${jsonEncode(data)}|$owner|$prevHash|$nonce');

  Map<String, dynamic> toJson() => {
        'index': index,
        'timestamp': timestamp,
        'type': type,
        'data': data,
        'owner': owner,
        'prevHash': prevHash,
        'nonce': nonce,
        'hash': hash,
      };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        index: j['index'],
        timestamp: j['timestamp'],
        type: j['type'],
        data: Map<String, dynamic>.from(j['data']),
        owner: j['owner'],
        prevHash: j['prevHash'],
        nonce: j['nonce'],
        hash: j['hash'],
      );
}

class Blockchain {
  /// Jumlah awalan '0' pada hash yang dibutuhkan (proof-of-work).
  static const difficulty = 3;
  static final _zeros = '0' * difficulty;
  static final genesisPrevHash = '0' * 64;

  static Block genesis() => mine(
      index: 0,
      timestamp: 0,
      type: 'genesis',
      data: const {},
      owner: 'system',
      prevHash: genesisPrevHash);

  /// Cari nonce sehingga hash diawali [difficulty] angka nol.
  static Block mine({
    required int index,
    required int timestamp,
    required String type,
    required Map<String, dynamic> data,
    required String owner,
    required String prevHash,
  }) {
    var nonce = 0;
    while (true) {
      final h = Block.computeHash(
        index: index,
        timestamp: timestamp,
        type: type,
        data: data,
        owner: owner,
        prevHash: prevHash,
        nonce: nonce,
      );
      if (h.startsWith(_zeros)) {
        return Block(
          index: index,
          timestamp: timestamp,
          type: type,
          data: data,
          owner: owner,
          prevHash: prevHash,
          nonce: nonce,
          hash: h,
        );
      }
      nonce++;
    }
  }

  static Block next(List<Block> chain, String type, Map<String, dynamic> data,
          String owner) =>
      mine(
        index: chain.length,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: type,
        data: data,
        owner: owner,
        prevHash: chain.last.hash,
      );

  /// Rantai valid jika: hash tiap blok cocok, memenuhi PoW, index berurutan,
  /// dan prevHash menunjuk hash blok sebelumnya.
  static bool isValid(List<Block> chain) {
    if (chain.isEmpty) return false;
    for (var i = 0; i < chain.length; i++) {
      final b = chain[i];
      final recomputed = Block.computeHash(
        index: b.index,
        timestamp: b.timestamp,
        type: b.type,
        data: b.data,
        owner: b.owner,
        prevHash: b.prevHash,
        nonce: b.nonce,
      );
      if (recomputed != b.hash || !b.hash.startsWith(_zeros)) return false;
      if (b.index != i) return false;
      if (i == 0
          ? b.prevHash != genesisPrevHash
          : b.prevHash != chain[i - 1].hash) {
        return false;
      }
    }
    return true;
  }

  /// Rantai dari server hanya boleh menggantikan rantai lokal bila:
  /// - blockchain-nya valid (hash + PoW + prevHash),
  /// - blok genesis-nya sama persis dengan lokal,
  /// - dan lebih panjang dari rantai lokal (lokal hanya genesis = pemulihan
  ///   perangkat baru).
  ///
  /// Selain itu rantai lokal dipertahankan, karena blok yang sudah di-mine
  /// tidak bisa disambung tanpa mining ulang.
  static bool canAdoptRemote(List<Block> local, List<Block> remote) {
    if (remote.isEmpty) return false;
    if (!isValid(remote)) return false;
    if (local.isEmpty) return false;
    if (local.first.hash != remote.first.hash) return false;
    // Rantai lokal hanya genesis: pulihkan seluruh rantai server.
    if (local.length == 1) return true;
    // Rantai lokal sudah berisi blok: hanya boleh kalau server lebih panjang
    // DAN sama persis sepanjang rantai lokal (rantai yang sama, bukan lain).
    if (remote.length <= local.length) return false;
    for (var i = 0; i < local.length; i++) {
      if (local[i].hash != remote[i].hash) return false;
    }
    return true;
  }
}
