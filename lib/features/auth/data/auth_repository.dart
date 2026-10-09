import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';
import '../../../core/utils/crypto_utils.dart';
import '../../../core/utils/jwt_utils.dart';

const _tokenKey = 'session_token';
const _expiryKey = 'session_expiry';
const _emailKey = 'user_email';

/// Cadangan kalau server tidak mengirim klaim `exp` pada token.
const fallbackSessionDuration = Duration(days: 7);

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

/// Galat autentikasi dengan pesan yang layak ditampilkan ke pengguna (U2).
///
/// Isinya sudah Bahasa Indonesia dan tidak pernah memuat `DioException` mentah,
/// `uri` internal, atau kode status yang tidak berguna bagi pengguna.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Petakan kegagalan jaringan/server menjadi kalimat Indonesia.
String describeAuthError(Object error) {
  if (error is AuthException) return error.message;
  if (error is DioException) {
    final code = error.response?.statusCode;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server tidak terjangkau. Coba beberapa saat lagi.';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi ke server. Cek internetmu.';
      case DioExceptionType.badCertificate:
        return 'Sertifikat server tidak valid.';
      case DioExceptionType.cancel:
        return 'Permintaan dibatalkan.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return _describeStatus(code, error.response?.data);
      default:
        return _describeStatus(code, error.response?.data);
    }
  }
  final text = error.toString();
  if (text.startsWith('Exception: ')) return text.substring(11);
  return text.isEmpty ? 'Gagal masuk.' : text;
}

/// 401/403 memang terjadi karena kredensial, jadi spesifik. Status lain
/// sebaiknya dijelaskan server, tapi kalau tidak ada pakai bawaan.
String _describeStatus(int? code, Object? body) {
  final fromServer = body is Map ? body['error']?.toString().trim() : null;
  if (code == 401 || code == 403) {
    return fromServer != null && fromServer.isNotEmpty
        ? fromServer
        : 'Email atau password salah.';
  }
  if (fromServer != null && fromServer.isNotEmpty) return fromServer;
  return code == null
      ? 'Gagal menghubungi server.'
      : 'Server menolak permintaan ($code). Coba lagi nanti.';
}

class AuthRepository {
  AuthRepository(
    this._dio,
    this._storage,
    this._localAuth, {
    String baseUrl = AppConfig.backendUrl,
    bool? allowMock,
  })  : _baseUrl = baseUrl,
        _allowMock = allowMock ?? mockAllowedByDefault;

  final Dio _dio;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final String _baseUrl;
  final bool _allowMock;

  bool get _usesSupabase => AppConfig.supabaseConfigured;

  /// U3: mode mock hanya untuk pengembangan. Di build rilis, login dan
  /// registrasi tanpa `BACKEND_URL` ditolak supaya tidak ada akun palsu yang
  /// berhasil masuk dan menyimpan data lokal yang tidak pernah sampai server.
  static bool get mockAllowedByDefault => !kReleaseMode;

  bool get isMock => _baseUrl.isEmpty;

  /// Melempar kalau aplikasi berjalan tanpa server di build rilis.
  void ensureMockAllowed(String action) {
    if (isMock && !_allowMock) {
      throw AuthException(
        'Build ini tidak punya alamat server, jadi "$action" dinonaktifkan.',
      );
    }
  }

  Future<void> login(String email, String password) async {
    final mail = email.trim();
    if (mail.isEmpty || password.isEmpty) {
      throw AuthException('Email dan password wajib diisi.');
    }
    if (_usesSupabase) {
      try {
        await supa.Supabase.instance.client.auth.signInWithPassword(
          email: mail,
          password: password,
        );
        return;
      } on supa.AuthException catch (e) {
        throw AuthException(e.message);
      } catch (e) {
        throw AuthException(describeAuthError(e));
      }
    }
    ensureMockAllowed('Masuk');

    // Hash SHA-256 dilakukan SEBELUM password dikirim ke backend.
    final hashed = CryptoUtils.sha256Hash(password);
    String token;

    if (isMock) {
      // Mode mock: backend belum tersedia.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      token = 'mock-${hashed.substring(0, 24)}';
    } else {
      final res =
          await _post('/auth/login', {'email': mail, 'password': hashed});
      final data = res.data;
      if (data is! Map || data['token'] is! String) {
        throw AuthException('Respons server tidak dikenali.');
      }
      token = data['token'] as String;
    }
    await _saveSession(token, mail);
  }

  /// U1: buat akun baru. Password di-hash di klien, jadi password asli tidak
  /// pernah meninggalkan perangkat.
  Future<void> register(String email, String password, String confirm) async {
    final mail = email.trim();
    if (mail.isEmpty || password.isEmpty) {
      throw AuthException('Email dan password wajib diisi.');
    }
    if (password != confirm) {
      throw AuthException('Konfirmasi password tidak sama.');
    }
    if (password.length < 8) {
      throw AuthException('Password minimal 8 karakter.');
    }
    if (_usesSupabase) {
      try {
        final response = await supa.Supabase.instance.client.auth.signUp(
          email: mail,
          password: password,
        );
        if (response.session == null) {
          throw AuthException(
            'Akun dibuat. Verifikasi email terlebih dahulu, lalu masuk.',
          );
        }
        return;
      } on supa.AuthException catch (e) {
        throw AuthException(e.message);
      } on AuthException {
        rethrow;
      } catch (e) {
        throw AuthException(describeAuthError(e));
      }
    }
    ensureMockAllowed('Daftar');

    final hashed = CryptoUtils.sha256Hash(password);
    if (isMock) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } else {
      try {
        final res =
            await _post('/auth/register', {'email': mail, 'password': hashed});
        if (res.data is! Map) {
          throw AuthException('Respons server tidak dikenali.');
        }
      } on DioException catch (e) {
        // U1: email sudah ada harus terbaca jelas, bukan "DioException 409".
        if (e.response?.statusCode == 409) {
          throw AuthException('Email sudah terdaftar. Silakan masuk.');
        }
        rethrow;
      }
    }
    // Langsung masuk supaya pengguna tidak mengetik ulang akun yang baru dibuat.
    await login(email, password);
  }

  /// POST ke server dengan galat jaringan sudah diterjemahkan (U2).
  Future<Response<dynamic>> _post(
      String path, Map<String, dynamic> data) async {
    try {
      return await _dio.post('$_baseUrl$path', data: data);
    } on DioException catch (e) {
      throw AuthException(describeAuthError(e));
    }
  }

  Future<void> _saveSession(String token, String email) async {
    await _storage.write(key: _tokenKey, value: token);
    // U5: masa berlaku ikut server (klaim `exp`), bukan tebakan 7 hari.
    final expiresAt =
        tokenExpiry(token) ?? DateTime.now().add(fallbackSessionDuration);
    await _storage.write(
      key: _expiryKey,
      value: expiresAt.millisecondsSinceEpoch.toString(),
    );
    await _storage.write(key: _emailKey, value: email);
  }

  /// Sesi valid = token ada DAN belum kedaluwarsa. Sesi kedaluwarsa dihapus.
  Future<bool> hasSession() async {
    if (_usesSupabase) {
      final session = supa.Supabase.instance.client.auth.currentSession;
      return session != null && !session.isExpired;
    }
    final token = await _storage.read(key: _tokenKey);
    final stored = int.tryParse(await _storage.read(key: _expiryKey) ?? '');
    if (token == null) return false;

    // `exp` dari server adalah acuan; nilai yang disimpan hanya cadangan untuk
    // token tanpa `exp` (misalnya token mock).
    final fromJwt = tokenExpiry(token);
    final expiry = fromJwt?.millisecondsSinceEpoch ?? stored;
    if (expiry == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > expiry) {
      await logout();
      return false;
    }
    return true;
  }

  Future<bool> canUseBiometric() async =>
      await _localAuth.isDeviceSupported() &&
      await _localAuth.canCheckBiometrics;

  Future<String?> userEmail() async {
    if (_usesSupabase) {
      return supa.Supabase.instance.client.auth.currentUser?.email;
    }
    return _storage.read(key: _emailKey);
  }

  /// Token JWT untuk endpoint yang butuh Authorization header.
  Future<String?> currentToken() async {
    if (_usesSupabase) {
      return supa.Supabase.instance.client.auth.currentSession?.accessToken;
    }
    return _storage.read(key: _tokenKey);
  }

  /// Biometrik hanya valid jika sudah pernah login (token tersimpan).
  Future<bool> authenticateBiometric() async {
    if (!await hasSession()) {
      throw AuthException('Login manual dulu minimal sekali.');
    }
    if (!await canUseBiometric()) {
      throw AuthException('Biometrik tidak tersedia di perangkat ini.');
    }
    final ok = await _localAuth.authenticate(
      localizedReason: 'Verifikasi identitas untuk masuk',
      options:
          const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
    if (!ok) throw AuthException('Autentikasi biometrik gagal.');
    return true;
  }

  /// U4: hapus sesi beserta private key wallet, supaya akun berikutnya tidak
  /// memakai dompet milik akun lama. Data pengguna di Hive dihapus oleh
  /// pemanggil lewat `clearUserData()`.
  Future<void> logout() async {
    if (_usesSupabase) {
      try {
        await supa.Supabase.instance.client.auth.signOut();
      } catch (_) {
        // Supabase menghapus session lokal sebelum mencoba mencabutnya di server.
      }
    }
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
    await _storage.delete(key: _emailKey);
    for (final key in AuthRepository.privateKeyKeys) {
      await _storage.delete(key: key);
    }
  }

  /// Kunci secure storage milik pengguna: sesi, email, dan private key wallet.
  static const privateKeyKeys = ['wallet_private_key'];

  /// Semua kunci Hive yang berisi data pengguna (U4).
  ///
  /// Sisa kunci non-pengguna (tema, alasan penolakan izin, cache jadwal liga)
  /// sengaja tidak dihapus: bukan data pribadi dan tidak memuat apa pun dari
  /// akun lama.
  static const userDataKeys = <String>[
    'away_day_expenses', // pengeluaran
    'away_day_budget_idr', // anggaran
    'score_predictions', // prediksi skor
    'passport_chain', // rantai blok + stamp
    'profile_photo_path', // foto profil
    'pam_feedback', // kesan dan saran
    'notified_results', // daftar laga yang sudah dinotifikasi
    'penalty_block_day', // harian penalty
    'last_sync_at', // waktu sinkronisasi
    'favorite_team', // tim favorit
  ];

  /// Prefiks kunci cache yang milik pengguna (pundit per klub).
  static const userKeyPrefixes = <String>['pundit_'];
}

final authRepositoryProvider = Provider((ref) => AuthRepository(
      ref.watch(dioProvider),
      ref.watch(secureStorageProvider),
      LocalAuthentication(),
    ));
