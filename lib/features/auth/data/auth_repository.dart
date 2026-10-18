import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/utils/app_config.dart';
import 'identity_store.dart';

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
  AuthRepository(
    this._storage,
    this._localAuth, {
    IdentityStore? identityStore,
    Future<void> Function(Map<String, dynamic>)? updateUserMetadata,
    Map<String, dynamic>? Function()? readUserMetadata,
  })  : identityStore = identityStore ?? HiveIdentityStore(),
        _updateUserMetadataOverride = updateUserMetadata,
        _readUserMetadataOverride = readUserMetadata;

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;
  final IdentityStore identityStore;
  final Future<void> Function(Map<String, dynamic>)?
      _updateUserMetadataOverride;
  final Map<String, dynamic>? Function()? _readUserMetadataOverride;

  bool get _usesSupabase =>
      AppConfig.supabaseConfigured ||
      _updateUserMetadataOverride != null ||
      _readUserMetadataOverride != null;
  String? get currentUserId =>
      _usesSupabase ? supa.Supabase.instance.client.auth.currentUser?.id : null;

  static String displayNameKey(String userId) => 'profile_display_name_$userId';
  static String profilePhotoKey(String userId) => 'profile_photo_path_$userId';
  static String favoriteTeamKey(String userId) => 'favorite_team_$userId';
  static String awayDayBudgetKey(String userId) =>
      'away_day_budget_idr_$userId';
  static String prefsPendingKey(String userId) => 'prefs_pending_$userId';
  static String displayNamePendingKey(String userId) => prefsPendingKey(userId);

  String? userScopedKey(String base) {
    final userId = currentUserId;
    return userId == null ? null : '${base}_$userId';
  }

  /// Reads a scoped value and migrates its legacy global value on first use.
  String? readUserScopedValue(String base) {
    final key = userScopedKey(base);
    if (key == null) return null;
    final scoped = identityStore.get(key);
    if (scoped != null) return scoped;
    final legacy = identityStore.get(base);
    if (legacy == null) return null;
    unawaited(() async {
      await identityStore.put(key, legacy);
      await identityStore.delete(base);
    }());
    return legacy;
  }

  Future<void> writeUserScopedValue(String base, String value) async {
    final key = userScopedKey(base);
    if (key != null) await identityStore.put(key, value);
  }

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

  /// Simpan nama tampilan ke metadata Supabase dan tandai kegagalan untuk retry.
  Future<bool> saveDisplayName(String name) async {
    final userId = currentUserId;
    if (!_usesSupabase || userId == null) return false;
    try {
      await _updateUserMetadata({'display_name': name});
      return true;
    } catch (_) {
      await identityStore.put(prefsPendingKey(userId), 'true');
      return false;
    }
  }

  Future<bool> saveProfilePrefs({String? favoriteTeam, int? budgetIdr}) async {
    final userId = currentUserId;
    if (!_usesSupabase || userId == null) return false;
    final data = <String, dynamic>{};
    if (favoriteTeam != null) data['favorite_team'] = favoriteTeam;
    if (budgetIdr != null) data['away_day_budget_idr'] = budgetIdr;
    if (data.isEmpty) return true;
    try {
      await _updateUserMetadata(data);
      return true;
    } catch (_) {
      await identityStore.put(prefsPendingKey(userId), 'true');
      return false;
    }
  }

  Future<void> retryPendingPrefs() async {
    final userId = currentUserId;
    if (userId == null ||
        identityStore.get(prefsPendingKey(userId)) != 'true') {
      return;
    }
    final name = identityStore.get(displayNameKey(userId));
    final favoriteTeam = identityStore.get(favoriteTeamKey(userId));
    final budget = identityStore.get(awayDayBudgetKey(userId));
    final data = <String, dynamic>{};
    if (name != null && name.isNotEmpty) data['display_name'] = name;
    if (favoriteTeam != null && favoriteTeam.isNotEmpty) {
      data['favorite_team'] = favoriteTeam;
    }
    final budgetIdr = int.tryParse(budget ?? '');
    if (budgetIdr != null) data['away_day_budget_idr'] = budgetIdr;
    if (data.isEmpty) {
      await identityStore.delete(prefsPendingKey(userId));
      return;
    }
    try {
      await _updateUserMetadata(data);
      await identityStore.delete(prefsPendingKey(userId));
    } catch (_) {
      // Keep the pending marker for the next authenticated startup.
    }
  }

  Future<void> retryPendingDisplayName() => retryPendingPrefs();

  Future<void> _updateUserMetadata(Map<String, dynamic> updates) async {
    final merged = {..._currentUserMetadata(), ...updates};
    final updateOverride = _updateUserMetadataOverride;
    if (updateOverride != null) {
      await updateOverride(merged);
      return;
    }
    await supa.Supabase.instance.client.auth.updateUser(
      supa.UserAttributes(data: merged),
    );
  }

  Map<String, dynamic> _currentUserMetadata() {
    final readOverride = _readUserMetadataOverride;
    if (readOverride != null) return readOverride() ?? const {};
    if (_updateUserMetadataOverride != null && !AppConfig.supabaseConfigured) {
      return const {};
    }
    return supa.Supabase.instance.client.auth.currentUser?.userMetadata ??
        const {};
  }

  /// Baca nama tampilan dari metadata pengguna Supabase yang sedang masuk.
  /// Mengembalikan null bila Supabase tidak dikonfigurasi atau tidak ada nama.
  String? cloudDisplayName() {
    if (!_usesSupabase) return null;
    final meta = _currentUserMetadata();
    final value = meta['display_name'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? cloudFavoriteTeam() => _cloudString('favorite_team');

  int? cloudBudgetIdr() {
    if (!_usesSupabase) return null;
    final meta = _currentUserMetadata();
    final value = meta['away_day_budget_idr'];
    return value is num ? value.round() : int.tryParse('$value');
  }

  String? _cloudString(String key) {
    if (!_usesSupabase) return null;
    final meta = _currentUserMetadata();
    final value = meta[key];
    return value is String && value.isNotEmpty ? value : null;
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
    'score_predictions', // prediksi skor
    'passport_chain', // rantai blok + stamp
    'notified_results', // daftar laga yang sudah dinotifikasi
    'penalty_block_day', // harian penalty
    'last_sync_at', // waktu sinkronisasi
  ];

  /// Prefiks kunci cache yang milik pengguna (pundit per klub).
  static const userKeyPrefixes = <String>['pundit_'];
}

final authRepositoryProvider = Provider((ref) => AuthRepository(
      ref.watch(secureStorageProvider),
      LocalAuthentication(),
    ));
