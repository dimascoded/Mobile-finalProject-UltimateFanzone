import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import 'user_data_cleanup.dart';

class AuthNotifier extends StateNotifier<AsyncValue<bool>> {
  AuthNotifier(this._repo, this._ref) : super(const AsyncData(false));
  final AuthRepository _repo;
  final Ref _ref;

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.login(email, password);
      return true;
    });
  }

  /// U1: daftar lalu langsung masuk.
  Future<void> register(String email, String password, String confirm) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.register(email, password, confirm);
      return true;
    });
  }

  Future<void> loginWithBiometric() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.authenticateBiometric);
  }

  /// Dipakai LockScreen: perangkat tanpa biometrik langsung lolos (sesi sudah valid).
  Future<void> unlock() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!await _repo.canUseBiometric()) return true;
      return _repo.authenticateBiometric();
    });
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
    await clearUserData();
    invalidateUserDataProviders(_ref);
    // Sesi dan email ikut kedaluwarsa supaya layar startup tidak mengira
    // pengguna masih masuk.
    _ref
      ..invalidate(sessionProvider)
      ..invalidate(userEmailProvider);
    state = const AsyncData(false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<bool>>(
    (ref) => AuthNotifier(ref.watch(authRepositoryProvider), ref));

/// Dipakai saat startup untuk memutuskan Login vs Dashboard.
final sessionProvider = FutureProvider<bool>(
    (ref) => ref.watch(authRepositoryProvider).hasSession());

final userEmailProvider = FutureProvider<String?>(
    (ref) => ref.watch(authRepositoryProvider).userEmail());
