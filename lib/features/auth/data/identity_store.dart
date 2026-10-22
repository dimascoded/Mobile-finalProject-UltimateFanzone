import '../../../core/database/hive_service.dart';

/// Abstraksi penyimpanan pasangan kunci-nilai untuk identitas/pengguna.
///
/// Diambil sebagai antarmuka supaya [AuthRepository] bisa diuji dengan
/// penyimpanan palsu, tanpa menyentuh Hive sungguhan. Lihat
/// `docs/feature-map.md` (bagian auth) untuk alur lengkapnya.
abstract interface class IdentityStore {
  /// Baca nilai [key], atau null bila belum pernah ditulis.
  String? get(String key);

  /// Tulis [value] ke [key], menimpa nilai lama bila ada.
  Future<void> put(String key, String value);

  /// Hapus [key] (tidak error bila kunci memang tidak ada).
  Future<void> delete(String key);
}

/// Implementasi [IdentityStore] di atas satu box Hive `app_cache`.
///
/// Semua nilai berupa String JSON/sederhana; skema versi dan migrasi ditangani
/// [HiveService], bukan di sini.
class HiveIdentityStore implements IdentityStore {
  @override
  String? get(String key) => HiveService.cache.get(key);

  @override
  Future<void> put(String key, String value) =>
      HiveService.cache.put(key, value);

  @override
  Future<void> delete(String key) => HiveService.cache.delete(key);
}
