import '../../gamification/data/blockchain.dart';

/// Keputusan rekonsiliasi rantai paspor antara salinan lokal dan cloud.
///
/// Cloud bersifat append-only (tabel `passport_chain_blocks` tidak bisa
/// diperbarui/dihapus dari aplikasi), jadi bila dua salinan berbeda, cloud
/// selalu menang dan blok lokal yang tidak ada di cloud dianggap tidak bisa
/// digabung.
enum ChainOutcome { pushLocal, inSync, adoptRemote }

/// Tentukan tindakan terhadap rantai lokal berdasarkan rantai cloud.
///
/// - Cloud kosong -> [ChainOutcome.pushLocal].
/// - Cloud tidak valid, atau genesis-nya berbeda saat lokal tidak kosong ->
///   lempar [StateError] (jangan menimpa apa pun).
/// - Lokal adalah awalan cloud dengan panjang sama -> [ChainOutcome.inSync].
/// - Lokal awalan ketat cloud (cloud lebih panjang) -> [ChainOutcome.adoptRemote].
/// - Cloud awalan ketat lokal (lokal lebih panjang) -> [ChainOutcome.pushLocal].
/// - Ada hash yang berbeda pada indeks bersama (bercabang) ->
///   [ChainOutcome.adoptRemote].
/// - Lokal hanya genesis -> [ChainOutcome.adoptRemote] bila cloud lebih
///   panjang, selain itu [ChainOutcome.inSync].
ChainOutcome reconcileChain(List<Block> local, List<Block> remote) {
  if (remote.isEmpty) return ChainOutcome.pushLocal;
  final invalidIndex = firstInvalidIndex(remote);
  if (invalidIndex != null) {
    throw StateError('Riwayat di cloud tidak valid (catatan #$invalidIndex).');
  }
  if (local.isNotEmpty && remote.first.hash != local.first.hash) {
    throw StateError('Riwayat di cloud berbeda genesis.');
  }
  if (local.isEmpty) return ChainOutcome.adoptRemote;

  // Lokal hanya genesis: perangkat baru, pulihkan seluruh rantai cloud.
  if (local.length == 1) {
    return remote.length > 1
        ? ChainOutcome.adoptRemote
        : ChainOutcome.inSync;
  }

  final minLength =
      local.length < remote.length ? local.length : remote.length;
  for (var i = 0; i < minLength; i++) {
    if (local[i].hash != remote[i].hash) return ChainOutcome.adoptRemote;
  }
  if (local.length == remote.length) return ChainOutcome.inSync;
  if (local.length < remote.length) return ChainOutcome.adoptRemote;
  return ChainOutcome.pushLocal;
}

/// Indeks blok pertama yang membuat rantai tidak valid, atau `null` bila
/// seluruh rantai valid. Bila seluruh rantai kosong dikembalikan `0`
/// (sebab [Blockchain.isValid] juga menolak rantai kosong).
///
/// Pemeriksaannya identik dengan [Blockchain.isValid]: urutan index,
/// tautan prevHash, hash yang dihitung ulang, dan awalan proof-of-work --
/// hanya bedanya di sini posisi kegagalannya dilaporkan, bukan sekadar
/// ya/tidak.
int? firstInvalidIndex(List<Block> chain) {
  if (chain.isEmpty) return 0;
  final zeros = '0' * Blockchain.difficulty;
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
    if (recomputed != b.hash || !b.hash.startsWith(zeros)) return i;
    if (b.index != i) return i;
    if (i == 0
        ? b.prevHash != Blockchain.genesisPrevHash
        : b.prevHash != chain[i - 1].hash) {
      return i;
    }
  }
  return null;
}

/// Urutkan baris rantai cloud menaik berdasarkan kolom `idx`.
///
/// PostgREST `.order()` memakai `ascending: false` secara bawaan, sehingga
/// baris bisa sampai terbalik (idx besar dulu). Rantai cloud sendiri selalu
/// bersifat append-only dan sejatinya urut `idx` menaik; tanpa pengurutan
/// ini [Blockchain.isValid] menolak rantai yang sebenarnya utuh.
List<Map<String, dynamic>> sortBlockRowsByIndex(
  List<Map<String, dynamic>> rows,
) {
  final sorted = List<Map<String, dynamic>>.of(rows);
  sorted.sort((a, b) => ((a['idx'] as num?)?.toInt() ?? 0)
      .compareTo((b['idx'] as num?)?.toInt() ?? 0));
  return sorted;
}

/// Jumlah blok lokal yang (indeks, hash)-nya tidak ada di cloud.
///
/// Blok seperti ini tidak bisa disambungkan kembali setelah adopsi cloud dan
/// TIDAK boleh ditambang ulang.
int droppedLocalBlocks(List<Block> local, List<Block> remote) {
  final remoteKeys = {
    for (final block in remote) '${block.index}:${block.hash}',
  };
  var dropped = 0;
  for (final block in local) {
    if (!remoteKeys.contains('${block.index}:${block.hash}')) dropped++;
  }
  return dropped;
}

/// Map satu baris tabel `passport_chain_blocks` ke bentuk JSON [Block].
///
/// Kolom cloud -> kunci [Block]:
/// - `idx` (integer) -> `index`
/// - `timestamp` (bigint, epoch milidetik) -> `timestamp` (int)
/// - `type` (text) -> `type`
/// - `data` (jsonb) -> `data`
/// - `owner` (text) -> `owner`
/// - `prev_hash` (text) -> `prevHash`
/// - `nonce` (bigint) -> `nonce` (int)
/// - `hash` (text) -> `hash`
Map<String, dynamic> blockRowToJson(Map<String, dynamic> row) => {
      'index': (row['idx'] as num?)?.toInt() ?? 0,
      'timestamp': (row['timestamp'] as num?)?.toInt() ?? 0,
      'type': row['type'] as String? ?? 'unknown',
      'data': row['data'] is Map
          ? Map<String, dynamic>.from(row['data'] as Map)
          : const <String, dynamic>{},
      'owner': row['owner'] as String? ?? '',
      'prevHash': row['prev_hash'] as String? ?? '',
      'nonce': (row['nonce'] as num?)?.toInt() ?? 0,
      'hash': row['hash'] as String? ?? '',
    };
