import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import 'blockchain.dart';

/// Baca/tulis rantai blok paspor.
///
/// Alur data: `chainProvider` memanggil [load]/[save]; penyimpanan utama lewat
/// `OfflineSyncDatabase.persist` (SQLite `sync_documents`, collection
/// `passport_chain`) dengan Hive `passport_chain` sebagai cermin/offline.
/// Lihat `docs/feature-map.md` (bagian gamification).
class ChainRepository {
  static const _key = 'passport_chain';

  /// Parse per-item (C2): blok rusak dilewati, blok lain tetap termuat.
  /// Kalau semuanya hilang, kembalikan genesis supaya aplikasi masih punya
  /// rantai yang valid daripada `load()` yang melempar.
  List<Block> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [Blockchain.genesis()];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return [Blockchain.genesis()];
    }
    if (decoded is! List) return [Blockchain.genesis()];
    final out = <Block>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      try {
        out.add(Block.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        continue;
      }
    }
    return out.isEmpty ? [Blockchain.genesis()] : out;
  }

  /// Simpan seluruh rantai sebagai JSON lewat jalur offline-first, sehingga
  /// revisi koleksi naik dan sinkronisasi ikut mengirim perubahannya.
  Future<void> save(List<Block> chain) => OfflineSyncDatabase.persist(
        _key,
        jsonEncode(chain.map((b) => b.toJson()).toList()),
      );
}

/// Penyedia [ChainRepository] tunggal.
final chainRepositoryProvider = Provider((ref) => ChainRepository());
