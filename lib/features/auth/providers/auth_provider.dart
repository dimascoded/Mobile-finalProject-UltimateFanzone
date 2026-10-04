import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';

class AuthNotifier extends StateNotifier<AsyncValue<bool>> {
  AuthNotifier(this._repo) : super(const AsyncData(false));
  final AuthRepository _repo;

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.login(email, password);
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

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<bool>>(
    (ref) => AuthNotifier(ref.watch(authRepositoryProvider)));

/// Dipakai saat startup untuk memutuskan Login vs Dashboard.
final sessionProvider =
    FutureProvider<bool>((ref) => ref.watch(authRepositoryProvider).hasSession());

final userEmailProvider =
    FutureProvider<String?>((ref) => ref.watch(authRepositoryProvider).userEmail());
