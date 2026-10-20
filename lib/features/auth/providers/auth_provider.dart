import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../data/auth_repository.dart';
import 'user_data_cleanup.dart';

class BiometricPreferenceNotifier extends StateNotifier<bool> {
  BiometricPreferenceNotifier({bool? initialState})
      : super(initialState ?? _load());

  static const _key = 'biometric_enabled';

  static bool _load() => HiveService.cache.get(_key) != 'false';

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await HiveService.cache.put(_key, enabled.toString());
  }
}

final biometricEnabledProvider =
    StateNotifierProvider<BiometricPreferenceNotifier, bool>(
  (ref) => BiometricPreferenceNotifier(),
);

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
  Future<void> register(String email, String password, String confirm) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.register(email, password, confirm);
      await _wipeIfAccountChanged();
      return true;
    });
    await _afterIdentitySuccess();
  }

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
  Future<void> logout() async {
    await _repo.logout();
    await _clearData();
    await _clearOfflineSync();
    invalidateUserDataProviders(_ref);
    state = const AsyncData(false);
    invalidateIdentityProviders(_ref);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<bool>>(
    (ref) => AuthNotifier(ref.watch(authRepositoryProvider), ref));

/// Dipakai saat startup untuk memutuskan Login vs Dashboard.
///
/// Saat ada sesi, user id aktif diklaim sebagai pemilik data lokal (H2), supaya
/// login akun berikutnya bisa membedakan akun yang sama vs akun berbeda.
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

final userEmailProvider = FutureProvider<String?>(
    (ref) => ref.watch(authRepositoryProvider).userEmail());
