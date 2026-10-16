/// Kebijakan kunci otomatis: setelah aplikasi dibiarkan di latar belakang
/// sekian lama, sesi valid diminta memverifikasi ulang identitas.
///
/// Murni Dart (tanpa Flutter) supaya bisa diuji tanpa widget.
class AutoLockPolicy {
  const AutoLockPolicy._();

  /// Lama aplikasi boleh di latar belakang sebelum dikunci lagi.
  static const timeout = Duration(seconds: 60);

  /// Putuskan apakah layar kunci perlu ditampilkan lagi.
  ///
  /// - [pausedAt] null berarti aplikasi tidak pernah dijeda;
  /// - kunci hanya berguna kalau biometrik aktif ([biometricEnabled]);
  /// - [suspended] true berarti ada aksi yang sengaja membuka dialog sistem
  ///   (kamera, galeri, prompt biometrik), jadi kunci ditahan.
  static bool shouldLock({
    required DateTime? pausedAt,
    required DateTime now,
    required bool biometricEnabled,
    bool suspended = false,
  }) {
    if (suspended || pausedAt == null || !biometricEnabled) return false;
    return now.difference(pausedAt) >= timeout;
  }
}
