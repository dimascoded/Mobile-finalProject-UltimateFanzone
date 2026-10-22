import 'dart:convert';
import '../../../core/utils/crypto_utils.dart';

/// Blockchain sederhana (Dart murni, tanpa dependensi Flutter -> mudah di-unit-test).
/// Tiap blok memuat hash blok sebelumnya + proof-of-work ringan.
///
/// Rantai blok disimpan pada koleksi Hive `passport_chain` (box `app_cache`),
/// yang juga ikut disinkronkan lewat tabel SQLite `sync_documents`
/// (collection `passport_chain`, bagian dari koleksi sinkron
/// `away_day_expenses`, `passport_chain`, `score_predictions`).
class Block {
  /// Membuat blok yang sudah ter-mine (hash sudah dihitung).
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

  /// Posisi blok dalam rantai (0 = genesis).
  final int index, timestamp, nonce;

  /// Jenis aksi blok (mis. `genesis`, `prediction_commit`, `prediction_result`).
  final String type;

  /// Pemilik blok (user id, atau `system` untuk genesis).
  final String owner;

  /// Hash blok sebelumnya; genesis memakai [Blockchain.genesisPrevHash].
  final String prevHash;

  /// Hash blok ini (hex SHA-256).
  final String hash;

  /// Muatan blok, mis. `{'match': 123, 'commit': '...'}`.
  final Map<String, dynamic> data;

  /// Hitung hash blok dari seluruh fieldnya.
  ///
  /// Susunan string yang di-hash: `index|timestamp|type|canonicalDataJson|
  /// owner|prevHash|nonce`. Bagian data selalu dinormalisasi lebih dulu
  /// (lihat [canonicalDataJson]) supaya hash sama di Dart, JavaScript, dan
  /// Postgres jsonb.
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
  ///
  /// Hasilnya dipakai sebagai salah satu bagian input hash blok
  /// (lihat [computeHash]), jadi perubahan di sini memengaruhi validitas
  /// seluruh rantai.
  static String canonicalDataJson(Map<String, dynamic> data) =>
      jsonEncode(_canonicalValue(data));

  /// Normalisasi rekursif: double bulat jadi int, key map diurutkan.
  ///
  /// Angka double yang melebihi batas integer tepat (2^53) tetap dibiarkan
  /// sebagai double supaya tidak kehilangan presisi.
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

  /// Serialisasi blok ke JSON (dipakai untuk penyimpanan & sinkronisasi).
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
  ///
  /// Sumbernya adalah JSON blok pada koleksi Hive `passport_chain`.
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

/// Utilitas rantai blok: mining proof-of-work dan validasi rantai.
///
/// Aturan main: setiap blok di-mine dengan hash SHA-256 yang diawali
/// [difficulty] angka nol; blok berikutnya menunjuk hash blok sebelumnya
/// lewat `prevHash`. Rantai disebut valid bila setiap blok.hash cocok dengan
/// hash yang dihitung ulang, memenuhi proof-of-work, `index` berurutan, dan
/// `prevHash` sesuai blok sebelumnya.
class Blockchain {
  /// Jumlah awalan '0' pada hash yang dibutuhkan (proof-of-work).
  ///
  /// Nilainya 3 berarti hash harus diawali "000"; menambah satu nol membuat
  /// mining jauh lebih lambat, jadi jangan diubah tanpa/definisi ulang
  /// rantai yang sudah ada.
  static const difficulty = 3;

  /// Awalan hash yang wajib dipenuhi proof-of-work.
  static final _zeros = '0' * difficulty;

  /// `prevHash` untuk blok genesis: 64 karakter nol.
  ///
  /// Nilainya dipakai [isValid] untuk memeriksa blok pertama dan
  /// [canAdoptRemote] untuk mencocokkan genesis lokal dengan server.
  static final genesisPrevHash = '0' * 64;

  /// Blok pertama rantai: index 0, timestamp 0, pemilik `system`, data kosong.
  ///
  /// Genesis di-mine dengan [difficulty] yang sama seperti blok lain, jadi
  /// hashnya selalu sama di semua perangkat.
  static Block genesis() => mine(
      index: 0,
      timestamp: 0,
      type: 'genesis',
      data: const {},
      owner: 'system',
      prevHash: genesisPrevHash);

  /// Cari nonce sehingga hash diawali [difficulty] angka nol.
  ///
  /// Nonce dihitung dari 0 naik satu per satu; blok yang dihasilkan selalu
  /// memenuhi proof-of-work sehingga [isValid] pasti menerimanya.
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

  /// Mine blok berikutnya untuk melewati rantai [chain].
  ///
  /// `index` = jumlah blok yang ada, `prevHash` = hash blok terakhir,
  /// `timestamp` = waktu sekarang dalam milidetik epoch.
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
  ///
  /// Rantai kosong dianggap tidak valid. Blok pertama wajib menunjuk
  /// [genesisPrevHash].
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
  ///
  /// Perbandingan dilakukan per blok (hash), bukan hanya panjang, supaya
  /// rantai server yang berbeda riwayat tidak pernah diterima.
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
