import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../data/auth_repository.dart';
import 'user_data_cleanup.dart';

/// Notifier preferensi biometrik (untuk layar kunci / masuk cepat).
///
/// State-nya `bool`: true berarti biometrik diizinkan dipakai. Nilai
/// disimpan di Hive `app_cache` (kunci `biometric_enabled`) sebagai string
/// `'true'`/`'false'`, dan TIDAK ikut terhapus saat logout karena ini
/// preferensi perangkat, bukan data pribadi.
///
/// Notifier tidak `autoDispose`, jadi tidak wajib cek `mounted` setelah
/// `await` (aturan §3.5 hanya berlaku untuk notifier `autoDispose`).
class BiometricPreferenceNotifier extends StateNotifier<bool> {
  BiometricPreferenceNotifier({bool? initialState})
      : super(initialState ?? _load());

  static const _key = 'biometric_enabled';

  static bool _load() => HiveService.cache.get(_key) != 'false';

  /// Set preferensi biometrik dan simpan ke Hive `app_cache`.
  ///
  /// Efek samping: menulis kunci `biometric_enabled`.
  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await HiveService.cache.put(_key, enabled.toString());
  }
}

/// Preferensi biometrik pengguna (true = biometrik boleh dipakai).
///
/// StateProvider biasa (bukan `autoDispose`) karena dibaca LockScreen dan
/// AuthNotifier; sumber penyimpanan ada di [BiometricPreferenceNotifier].
final biometricEnabledProvider =
    StateNotifierProvider<BiometricPreferenceNotifier, bool>(
  (ref) => BiometricPreferenceNotifier(),
);

/// Notifier status autentikasi.
///
/// State-nya `AsyncValue<bool>`: `AsyncData(true)` berarti berhasil masuk,
/// `AsyncData(false)` berarti belum masuk (setelah logout), `AsyncLoading`
/// selama proses berjalan, `AsyncError` berisi pesan galat Bahasa
/// Indonesia yang layak ditampilkan.
///
/// Tanggung jawab notifier ini:
///
/// - menjalankan login/register/login biometrik/unlock lewat
///   [AuthRepository];
/// - membersihkan data akun sebelumnya saat terjadi pergantian akun
///   (lihat [_wipeIfAccountChanged]);
/// - mengirim ulang prefs yang tertunda ke metadata akun setelah berhasil
///   masuk, lalu meng-invalidate provider identitas.
///
/// Notifier tidak `autoDispose` (sesi harus bertahan sepanjang hidup
/// aplikasi), jadi tidak wajib cek `mounted` setelah `await` (aturan §3.5
/// hanya berlaku untuk notifier `autoDispose`).
class AuthNotifier extends StateNotifier<AsyncValue<bool>> {
  AuthNotifier(this._repo, this._ref,
      {Future<void> Function()? clearData,
      Future<void> Function()? clearOfflineSync})
      : _clearData = clearData ?? clearUserData,
        _clearOfflineSync = clearOfflineSync ?? OfflineSyncDatabase.clear,
        super(const AsyncData(false));
  final AuthRepository _repo;
  final Ref _ref;
  final Future<void> Function() _clearData;
  final Future<void> Function() _clearOfflineSync;

  /// Tindakan setelah autentikasi berhasil: kirim ulang prefs yang tertunda
  /// ke metadata akun lalu invalidasi provider identitas.
  ///
  /// Hanya dijalankan bila state terakhir benar-benar sukses, jadi gagal
  /// login tidak memicu invalidasi yang tidak perlu.
  Future<void> _afterIdentitySuccess() async {
    if (state.valueOrNull != true) return;
    await _repo.retryPendingPrefs();
    invalidateIdentityProviders(_ref);
  }

  /// Ganti akun (H1): bersihkan data akun sebelumnya SEBELUM state di-set
  /// sukses, supaya Dashboard tidak sempat memuat/menyinkronkan data akun lama
  /// yang masih tersimpan di Hive, OfflineSyncDatabase, dan provider memori.
  ///
  /// Provider data konten di-invalidate di sini (masih di dalam guard);
  /// invalidasi identitas (email, nama, foto, favorit) tetap berjalan di
  /// [_afterIdentitySuccess] tepat setelah state sukses — satu gelombang saja,
  /// sama seperti perilaku sebelum fitur ganti akun ada.
  ///
  /// Kebijakan: pemilik data tidak diketahui (null) dianggap asing dan ikut
  /// di-wipe — data yatim tidak pernah diasumsikan milik akun yang baru. Akun
  /// dengan id yang SAMA mempertahankan data lokal agar kontinuitas offline
  /// tetap ada. H4: tanpa user id (mis. register yang belum punya sesi) tidak
  /// ada yang bisa dilakukan, jadi dilewati.
  Future<void> _wipeIfAccountChanged() async {
    final userId = _repo.currentUserId;
    if (userId == null) return;
    if (readDataOwnerId(_repo.identityStore) == userId) return;
    await _clearData();
    await _clearOfflineSync();
    invalidateUserContentProviders(_ref);
    await writeDataOwnerId(_repo.identityStore, userId);
  }

  /// Masuk dengan email dan password.
  ///
  /// Set state ke `AsyncLoading` lalu `AsyncValue.guard` di atas
  /// [AuthRepository.login]. Bila akun yang masuk berbeda dari pemilik data
  /// lokal sebelumnya, data akun lama dihapus lebih dulu (lihat
  /// [_wipeIfAccountChanged]). Efek samping: sesi Supabase dibuat, data Hive
  /// dan SQLite bisa dihapus, dan provider konten/invalidate identitas
  /// dijalankan.
  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.login(email, password);
      await _wipeIfAccountChanged();
      return true;
    });
    await _afterIdentitySuccess();
  }

  /// U1: daftar lalu langsung masuk.
  ///
  /// Alur dan efek sampingnya sama dengan [login]; perbedaannya hanya
  /// pemanggilan [AuthRepository.register] yang lebih dulu memvalidasi
  /// konfirmasi password dan panjang minimal password.
  Future<void> register(String email, String password, String confirm) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.register(email, password, confirm);
      await _wipeIfAccountChanged();
      return true;
    });
    await _afterIdentitySuccess();
  }

  /// Masuk cepat memakai biometrik.
  ///
  /// Menolak dengan [AuthException] bila biometrik dimatikan di Profil
  /// ([biometricEnabledProvider]); selain itu memanggil
  /// [AuthRepository.authenticateBiometric] yang memverifikasi sidik jari.
  /// Efek samping: sesi Supabase dibuka kembali, prefs tertunda dikirim
  /// ulang, dan provider identitas di-invalidate.
  Future<void> loginWithBiometric() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!_ref.read(biometricEnabledProvider)) {
        throw AuthException('Biometrik dinonaktifkan di Profil.');
      }
      return _repo.authenticateBiometric();
    });
    await _afterIdentitySuccess();
  }

  /// Dipakai LockScreen: perangkat tanpa biometrik langsung lolos (sesi sudah valid).
  ///
  /// Bila biometrik dimatikan atau perangkat tidak mendukungnya, Unlock
  /// dianggap berhasil tanpa memeriksa apa pun. Bila biometrik aktif, memanggil
  /// [AuthRepository.authenticateBiometric]. Efek samping: prefs tertunda
  /// dikirim ulang dan provider identitas di-invalidate.
  Future<void> unlock() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!_ref.read(biometricEnabledProvider)) return true;
      if (!await _repo.canUseBiometric()) return true;
      return _repo.authenticateBiometric();
    });
    await _afterIdentitySuccess();
  }

  /// U4: keluar dari akun dan bersihkan semua jejak data pengguna.
  ///
  /// Token, email, dan private key wallet dihapus dari secure storage; data
  /// pengguna di Hive (pengeluaran, prediksi, rantai, foto profil, saran,
  /// favorit, cache Pundit) dihapus; provider yang masih menyimpan data lama di
  /// memori dibuang. Sisa prefs perangkat seperti tema dan alasan penolakan
  /// izin tidak dihapus karena bukan data pribadi.
  ///
  /// Efek samping konkretnya: sesi Supabase dicabut dan kunci secure storage
  /// `wallet_private_key` dihapus ([AuthRepository.logout]); data pengguna di
  /// Hive `app_cache` dihapus (kunci `away_day_expenses`, `score_predictions`,
  /// `passport_chain`, `notified_results`, `penalty_block_day`, `last_sync_at`,
  /// kunci berawalan `pundit_`, dan kunci identitas legacy) serta seluruh baris
  /// SQLite `sync_documents` dan `sync_deletions` dikosongkan; provider
  /// konten dan identitas di-invalidate.
  ///
  /// Catatan: kunci `last_user_id` (pemilik data lokal) SENGAJA TIDAK
  /// dihapus, supaya login berikutnya bisa mendeteksi pergantian akun.
  Future<void> logout() async {
    await _repo.logout();
    await _clearData();
    await _clearOfflineSync();
    invalidateUserDataProviders(_ref);
    state = const AsyncData(false);
    invalidateIdentityProviders(_ref);
  }
}

/// Status autentikasi aplikasi: `AsyncValue<bool>` yang menyatakan apakah
/// pengguna sedang masuk.
///
/// StateProvider biasa (bukan `autoDispose`) karena session menentukan
/// navigasi root aplikasi; sumber perilakunya ada di [AuthNotifier].
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<bool>>(
    (ref) => AuthNotifier(ref.watch(authRepositoryProvider), ref));

/// Dipakai saat startup untuk memutuskan Login vs Dashboard.
///
/// Saat ada sesi, user id aktif diklaim sebagai pemilik data lokal (H2), supaya
/// login akun berikutnya bisa membedakan akun yang sama vs akun berbeda.
///
/// Efek samping: [AuthRepository.retryPendingPrefs] mengirim ulang prefs yang
/// tertunda ke metadata akun, dan user id ditulis ke Hive `app_cache` dengan
/// kunci `last_user_id` (lihat [writeDataOwnerId]). Kunci itu SENGAJA tidak
/// ikut terhapus saat logout supaya deteksi pergantian akun tetap bekerja.
final sessionProvider = FutureProvider<bool>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  final hasSession = await repo.hasSession();
  if (hasSession) {
    await repo.retryPendingPrefs();
    final userId = repo.currentUserId;
    if (userId != null) await writeDataOwnerId(repo.identityStore, userId);
  }
  return hasSession;
});

/// Email pengguna yang sedang masuk (null bila belum masuk / Supabase belum
/// dikonfigurasi).
///
/// Provider async sederhana yang membaca sesi Supabase lewat
/// [AuthRepository.userEmail]. Tanpa efek samping; invalidate-nya dilakukan
/// bersama provider identitas lain saat logout atau pergantian akun.
final userEmailProvider = FutureProvider<String?>(
    (ref) => ref.watch(authRepositoryProvider).userEmail());
