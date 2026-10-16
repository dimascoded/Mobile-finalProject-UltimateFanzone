import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/utils/app_config.dart';

/// Pesan saat env Supabase belum diisi, jadi autentikasi tidak mungkin jalan.
const notConfiguredAuthMessage =
    'Aplikasi belum dikonfigurasi. Isi SUPABASE_URL dan SUPABASE_ANON_KEY di env.json lalu jalankan ulang.';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

/// Galat autentikasi dengan pesan yang layak ditampilkan ke pengguna (U2).
///
/// Isinya sudah Bahasa Indonesia dan tidak pernah memuat galat mentah,
/// `uri` internal, atau kode status yang tidak berguna bagi pengguna.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Petakan kegagalan autentikasi menjadi kalimat Indonesia.
String describeAuthError(Object error) {
  if (error is AuthException) return error.message;
  if (error is supa.AuthException) return _mapSupabaseAuthError(error);
  if (error is SocketException) {
    return 'Tidak ada koneksi ke server. Cek internetmu.';
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Tidak ada koneksi ke server. Cek internetmu.';
      default:
        break;
    }
  }
  final text = error.toString();
  if (text.startsWith('Exception: ')) return text.substring(11);
  return text.isEmpty ? 'Gagal masuk.' : text;
}

/// Petakan galat Supabase Auth ke Bahasa Indonesia. `code` dipakai lebih dulu
/// karena stabil; kalau tidak ada, petakan dari pesan yang sudah di-lowercase.
String _mapSupabaseAuthError(supa.AuthException e) {
  switch (e.code) {
    case 'invalid_credentials':
      return 'Email atau password salah.';
    case 'email_not_confirmed':
      return 'Email belum diverifikasi. Cek kotak masuk emailmu.';
    case 'user_already_exists':
      return 'Email sudah terdaftar. Silakan masuk.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.';
    case 'weak_password':
      return 'Password terlalu lemah. Gunakan minimal 8 karakter.';
  }
  final message = e.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Email atau password salah.';
  }
  if (message.contains('email not confirmed')) {
    return 'Email belum diverifikasi. Cek kotak masuk emailmu.';
  }
  if (message.contains('already registered') ||
      message.contains('already exists')) {
    return 'Email sudah terdaftar. Silakan masuk.';
  }
  if (message.contains('rate limit') || message.contains('too many requests')) {
    return 'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.';
  }
  if (message.contains('weak password')) {
    return 'Password terlalu lemah. Gunakan minimal 8 karakter.';
  }
  return e.message.isNotEmpty ? e.message : 'Gagal masuk.';
}

/// Autentikasi hanya lewat Supabase Auth.
class AuthRepository {
  AuthRepository(this._storage, this._localAuth);

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  bool get _usesSupabase => AppConfig.supabaseConfigured;

  Future<void> login(String email, String password) async {
    final mail = email.trim();
    if (mail.isEmpty || password.isEmpty) {
      throw AuthException('Email dan password wajib diisi.');
    }
    if (!_usesSupabase) {
      throw AuthException(notConfiguredAuthMessage);
    }
    try {
      await supa.Supabase.instance.client.auth.signInWithPassword(
        email: mail,
        password: password,
      );
    } on supa.AuthException catch (e) {
      throw AuthException(_mapSupabaseAuthError(e));
    } catch (e) {
      throw AuthException(describeAuthError(e));
    }
  }

  /// Verifikasi password akun yang sedang masuk TANPA menghapus data apa pun.
  ///
  /// Dipakai layar kunci sebagai alternatif biometrik: email diambil dari sesi
  /// yang sudah ada, jadi pengguna tidak perlu mengetiknya lagi. Beda dari
  /// [login] yang memulai sesi baru, kegagalan di sini hanya menghasilkan
  /// [AuthException] dan tidak menyentuh data pengguna di Hive/secure storage.
  Future<void> verifyPassword(String password) async {
    if (password.isEmpty) {
      throw AuthException('Password wajib diisi.');
    }
    if (!_usesSupabase) {
      throw AuthException(notConfiguredAuthMessage);
    }
    final email = supa.Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw AuthException('Sesi tidak ditemukan. Masuk ulang dengan password.');
    }
    try {
      final response = await supa.Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      if (response.session == null) {
        throw AuthException('Email atau password salah.');
      }
    } on supa.AuthException catch (e) {
      throw AuthException(_mapSupabaseAuthError(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(describeAuthError(e));
    }
  }

  /// Buat akun baru lewat Supabase. Kalau Supabase meminta verifikasi email,
  /// tidak ada sesi yang dikembalikan dan pengguna diarahkan untuk masuk.
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
    if (!_usesSupabase) {
      throw AuthException(notConfiguredAuthMessage);
    }
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
    } on supa.AuthException catch (e) {
      throw AuthException(_mapSupabaseAuthError(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(describeAuthError(e));
    }
  }

  /// Sesi valid kalau Supabase punya sesi yang belum kedaluwarsa.
  Future<bool> hasSession() async {
    if (!_usesSupabase) return false;
    final session = supa.Supabase.instance.client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  Future<bool> canUseBiometric() async =>
      await _localAuth.isDeviceSupported() &&
      await _localAuth.canCheckBiometrics;

  Future<String?> userEmail() async {
    if (!_usesSupabase) return null;
    return supa.Supabase.instance.client.auth.currentUser?.email;
  }

  /// Token JWT Supabase untuk endpoint yang butuh Authorization header.
  Future<String?> currentToken() async {
    if (!_usesSupabase) return null;
    return supa.Supabase.instance.client.auth.currentSession?.accessToken;
  }

  /// Biometrik hanya valid jika sudah pernah login (sesi Supabase ada).
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
    for (final key in AuthRepository.privateKeyKeys) {
      await _storage.delete(key: key);
    }
  }

  /// Kunci secure storage milik pengguna: private key wallet.
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
      ref.watch(secureStorageProvider),
      LocalAuthentication(),
    ));
