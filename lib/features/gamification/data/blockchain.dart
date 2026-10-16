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
          '$index|$timestamp|$type|${canonicalDataJson(data)}|$owner|$prevHash|$nonce');

  /// Bentuk JSON kanonik yang identik di Dart, JavaScript, dan Postgres jsonb.
  ///
  /// Dua normalisasi dilakukan sebelum encode supaya teks hasilnya selalu sama
  /// di ketiga sisi:
  ///   1. Key setiap map diurutkan menaik dengan perbandingan ordinal string
  ///      (recursif, termasuk map di dalam list). Supabase menyimpan `data`
  ///      sebagai jsonb yang mengurutkan ulang key, dan `JSON.stringify` di
  ///      Node memakai urutan parse; tanpa pengurutan ini hash yang dihitung
  ///      ulang dari baris cloud tidak akan pernah cocok.
  ///   2. Double tanpa bagian desimal dinormalkan menjadi int, karena
  ///      `jsonEncode(1500.0)` di Dart menghasilkan `1500.0` sementara
  ///      `JSON.stringify` di Node menghasilkan `1500`.
  static String canonicalDataJson(Map<String, dynamic> data) =>
      jsonEncode(_canonicalValue(data));

  static Object? _canonicalValue(Object? value) {
    if (value is double) {
      final whole = value.isFinite && value == value.roundToDouble();
      return whole && value.abs() <= 9007199254740992 ? value.toInt() : value;
    }
    if (value is Map) {
      final entries = value.entries
          .map((e) => MapEntry(e.key.toString(), _canonicalValue(e.value)))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return Map.fromEntries(entries);
    }
    if (value is List) return value.map(_canonicalValue).toList();
    return value;
  }

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

  /// Parse toleran (C2): field yang hilang atau salah tipe tidak boleh membuat
  /// seluruh rantai hilang. `hash` yang kosong dipakai agar blok tetap bisa
  /// dihitung ulang; `chainValidProvider` yang akan menandainya tidak valid.
  factory Block.fromJson(Map<String, dynamic> j) => Block(
        index: (j['index'] as num?)?.toInt() ?? 0,
        timestamp: (j['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        type: (j['type'] as String?)?.trim().isNotEmpty == true
            ? (j['type'] as String).trim()
            : 'unknown',
        data: j['data'] is Map
            ? Map<String, dynamic>.from(j['data'] as Map)
            : const <String, dynamic>{},
        owner: (j['owner'] as String?) ?? '',
        prevHash: (j['prevHash'] as String?) ?? '',
        nonce: (j['nonce'] as num?)?.toInt() ?? 0,
        hash: (j['hash'] as String?) ?? '',
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
