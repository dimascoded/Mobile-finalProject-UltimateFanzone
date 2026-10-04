import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../../core/utils/crypto_utils.dart';

const _tokenKey = 'session_token';
const _expiryKey = 'session_expiry';
const sessionDuration = Duration(days: 7);

final secureStorageProvider =
    Provider((ref) => const FlutterSecureStorage());

class AuthRepository {
  AuthRepository(this._dio, this._storage, this._localAuth);
  final Dio _dio;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<void> login(String email, String password) async {
    // Hash SHA-256 dilakukan SEBELUM password dikirim ke backend.
    final hashed = CryptoUtils.sha256Hash(password);
    String token;

    if (AppConfig.backendUrl.isEmpty) {
      // Mode mock: backend belum tersedia.
      await Future.delayed(const Duration(milliseconds: 600));
      if (email.trim().isEmpty || password.isEmpty) {
        throw Exception('Email dan password wajib diisi');
      }
      token = 'mock-${hashed.substring(0, 24)}';
    } else {
      final res = await _dio.post(
        '${AppConfig.backendUrl}/auth/login',
        data: {'email': email.trim(), 'password': hashed},
      );
      if (res.statusCode != 200) throw Exception('Login gagal (${res.statusCode})');
      token = res.data['token'] as String;
    }
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(
      key: _expiryKey,
      value: DateTime.now().add(sessionDuration).millisecondsSinceEpoch.toString(),
    );
    await _storage.write(key: 'user_email', value: email.trim());
  }

  /// Sesi valid = token ada DAN belum kedaluwarsa. Sesi kedaluwarsa dihapus.
  Future<bool> hasSession() async {
    final token = await _storage.read(key: _tokenKey);
    final expiry = int.tryParse(await _storage.read(key: _expiryKey) ?? '');
    if (token == null || expiry == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > expiry) {
      await logout();
      return false;
    }
    return true;
  }

  Future<bool> canUseBiometric() async =>
      await _localAuth.isDeviceSupported() && await _localAuth.canCheckBiometrics;

  Future<String?> userEmail() => _storage.read(key: 'user_email');

  /// Token JWT untuk endpoint yang butuh Authorization header.
  Future<String?> currentToken() => _storage.read(key: _tokenKey);

  /// Biometrik hanya valid jika sudah pernah login (token tersimpan).
  Future<bool> authenticateBiometric() async {
    if (!await hasSession()) throw Exception('Login manual dulu minimal sekali');
    if (!await canUseBiometric()) throw Exception('Biometrik tidak tersedia di perangkat ini');
    return _localAuth.authenticate(
      localizedReason: 'Verifikasi identitas untuk masuk',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository(
      ref.watch(dioProvider),
      ref.watch(secureStorageProvider),
      LocalAuthentication(),
    ));
