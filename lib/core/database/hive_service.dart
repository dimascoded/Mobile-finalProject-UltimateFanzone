import 'package:hive_flutter/hive_flutter.dart';

/// Penyimpanan lokal (Hive) untuk cache dan data pengguna.
///
/// Versi skema disimpan di key [_schemaVersionKey]. Saat versi di disk lebih
/// kecil dari [_currentSchemaVersion], [init] menjalankan migrasi sebelum box
/// lain dibaca, sehingga data dari versi aplikasi sebelumnya tidak hilang
/// diam-diam.
class HiveService {
  HiveService._();

  static const _boxName = 'app_cache';
  static const _schemaVersionKey = 'schema_version';

  /// Naikkan setiap kali bentuk data yang disimpan berubah.
  ///
  /// 1 — awal: cache prediksi, pengeluaran, chain, profil, kurs.
  static const _currentSchemaVersion = 1;

  static late Box<String> cache;

  static Future<void> init() async {
    await Hive.initFlutter();
    cache = await Hive.openBox<String>(_boxName);
    await _migrate();
  }

  static int get schemaVersion =>
      int.tryParse(cache.get(_schemaVersionKey) ?? '') ?? 0;

  static Future<void> _migrate() async {
    final from = schemaVersion;
    if (from >= _currentSchemaVersion) return;

    // Tidak ada migrasi data untuk versi < 1: itu format pertama yang pernah
    // dipakai, jadi yang perlu hanya menandai skema sebagai dikenal supaya
    // migrasi tidak dijalankan ulang tiap start.
    //
    // Contoh cara menambah migrasi di masa depan:
    //   if (from < 2) { await _renameKey('lama', 'baru'); }
    if (from < 1) {
      // Tidak ada data yang perlu ditulis ulang.
    }
    await cache.put(_schemaVersionKey, '$_currentSchemaVersion');
  }

  /// Salin nilai satu key ke nama baru lalu hapus yang lama. Dipakai migrasi
  /// saat nama key berubah.
  static Future<void> renameKey(String oldKey, String newKey) async {
    final v = cache.get(oldKey);
    if (v == null) return;
    await cache.put(newKey, v);
    await cache.delete(oldKey);
  }
}
