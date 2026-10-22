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
///
/// Ini yang tampil pada mode mock: aplikasi tetap bisa dibangun tanpa
/// `env.json`, tapi semua operasi yang butuh server (login, daftar, simpan
/// metadata) berhenti dengan pesan ini — tidak ada sesi palsu yang diam-diam
/// dibuat.
const notConfiguredAuthMessage =
    'Aplikasi belum dikonfigurasi. Isi SUPABASE_URL dan SUPABASE_ANON_KEY di env.json lalu jalankan ulang.';

/// Penyedia [FlutterSecureStorage] untuk menyimpan kunci privat dompet.
///
/// Satu-satunya kunci yang ditulis aplikasi ke secure storage adalah
/// `wallet_private_key` (lihat [AuthRepository.privateKeyKeys]). Token sesi
/// milik Supabase dikelola sendiri oleh SDK Supabase dan TIDAK ditulis ke
/// secure storage, jadi aplikasi ini tidak punya kunci `session_token`,
/// `session_expiry`, atau `user_email` sendiri.
final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

/// Galat autentikasi dengan pesan yang layak ditampilkan ke pengguna (U2).
///
/// Isinya sudah Bahasa Indonesia dan tidak pernah memuat galat mentah,
/// `uri` internal, atau kode status yang tidak berguna bagi pengguna.
class AuthException implements Exception {
  /// Membangun galat dengan pesan final yang langsung ditampilkan ke pengguna.
  AuthException(this.message);

  /// Pesan galat dalam Bahasa Indonesia, siap tampil tanpa format tambahan.
  final String message;

  /// Mengembalikan pesan galat apa adanya, supaya galat yang dilempar bisa
  /// langsung ditampilkan tanpa parsing tambahan.
  @override
  String toString() => message;
}

/// Petakan kegagalan autentikasi menjadi kalimat Indonesia.
///
/// Sumber pesan, berurutan dari yang paling spesifik:
/// 1. [AuthException] — pesan sudah jadi kalimat Indonesia, dipakai apa adanya.
/// 2. `supa.AuthException` — dipetakan lewat [_mapSupabaseAuthError].
/// 3. [SocketException] dan galat jaringan Dio — jadi "Tidak ada koneksi
///    ke server. Cek internetmu."
/// 4. Galat lain — diambil dari `toString()`; awalan "Exception: " dibuang
///    supaya tidak tampil mentah ke pengguna.
///
/// Kembalikan string, bukan objek galat: pemanggil cukup memakainya sebagai
/// teks di snackbar/dialog tanpa perlu membungkus lagi.
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
///
/// Daftar kode yang dikenali: `invalid_credentials`, `email_not_confirmed`,
/// `user_already_exists`, `over_request_rate_limit`,
/// `over_email_send_rate_limit`, dan `weak_password`. Kode lain jatuh ke
/// pencocokan pesan, lalu ke pesan asli Supabase sebagai upaya terakhir.
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

/// Sumber kebenaran autentikasi dan preferensi profil pengguna.
///
/// Alur: seluruh autentikasi lewat Supabase Auth (alias `supa`), jadi sesi,
/// email, dan token JWT dibaca langsung dari klien Supabase. Preferensi
/// profil (nama tampilan, foto profil, tim favorit, anggaran away day)
/// disimpan dua kali:
///
/// - Lokal di Hive box `app_cache` dengan kunci ber-sufiks user id, misalnya
///   `profile_display_name_<userId>` ([displayNameKey]),
///   `profile_photo_path_<userId>` ([profilePhotoKey]),
///   `favorite_team_<userId>` ([favoriteTeamKey]), dan
///   `away_day_budget_idr_<userId>` ([awayDayBudgetKey]).
/// - Di metadata Supabase (`display_name`, `favorite_team`,
///   `away_day_budget_idr`) sebagai cadangan cloud yang bisa diambil ulang
///   di perangkat lain.
///
/// Kegagalan menulis ke cloud tidak menghapus data lokal: penanda
/// `prefs_pending_<userId>` ([prefsPendingKey]) disisipkan supaya
/// [retryPendingPrefs] dapat mengirim ulangnya pada start berikutnya.
///
/// Mode mock: bila Supabase belum dikonfigurasi ([AppConfig.supabaseConfigured]
/// kosong) dan tidak ada hook injeksi, semua operasi autentikasi berhenti
/// dengan [notConfiguredAuthMessage] — tidak ada login lokal/"offline" yang
/// menyamar sebagai login sungguhan.
class AuthRepository {
  /// Membuat repository dengan [_storage] (secure storage) dan [_localAuth]
  /// (biometrik perangkat).
  ///
  /// [updateUserMetadata] dan [readUserMetadata] adalah hook injeksi yang
  /// dipakai test agar repository bisa diuji tanpa Supabase sungguhan.
  /// [identityStore] bisa diganti dengan penyimpanan palsu; bawaannya
  /// [HiveIdentityStore] (Hive box `app_cache`).
  AuthRepository(
    this._storage,
    this._localAuth, {
    IdentityStore? identityStore,
    Future<void> Function(Map<String, dynamic>)? updateUserMetadata,
    Map<String, dynamic>? Function()? readUserMetadata,
  })  : identityStore = identityStore ?? HiveIdentityStore(),
        _updateUserMetadataOverride = updateUserMetadata,
        _readUserMetadataOverride = readUserMetadata;

  /// Secure storage untuk kunci privat dompet (`wallet_private_key`).
  final FlutterSecureStorage _storage;

  /// APIs biometrik/face-id perangkat.
  final LocalAuthentication _localAuth;

  /// Penyimpanan lokal nilai preferensi (Hive box `app_cache`).
  final IdentityStore identityStore;

  final Future<void> Function(Map<String, dynamic>)?
      _updateUserMetadataOverride;
  final Map<String, dynamic>? Function()? _readUserMetadataOverride;

  /// True bila repository boleh menyentuh Supabase.
  ///
  /// Benar bila Supabase dikonfigurasi ([AppConfig.supabaseConfigured]) atau
  /// ada hook injeksi metadata. Bila false, repository operate sebagai mode
  /// mock: operasi yang butuh server melempar [notConfiguredAuthMessage].
  bool get _usesSupabase =>
      AppConfig.supabaseConfigured ||
      _updateUserMetadataOverride != null ||
      _readUserMetadataOverride != null;

  /// Id user Supabase yang sedang masuk, atau null bila belum ada sesi.
  ///
  /// Dipakai sebagai sufiks semua kunci Hive per-pengguna, jadi nilai ini
  /// menentukan file mana yang "milik" pengguna aktif.
  String? get currentUserId =>
      _usesSupabase ? supa.Supabase.instance.client.auth.currentUser?.id : null;

  /// Kunci Hive untuk nama tampilan pengguna.
  ///
  /// Format: `profile_display_name_<userId>`. Nilai legacy tanpa sufiks
  /// (`profile_display_name`) diadopsi lewat [readUserScopedValue].
  static String displayNameKey(String userId) => 'profile_display_name_$userId';

  /// Kunci Hive untuk lokasi foto profil (path file lokal).
  ///
  /// Format: `profile_photo_path_<userId>`. Nilai legacy tanpa sufiks
  /// (`profile_photo_path`) diadopsi lewat [readUserScopedValue].
  static String profilePhotoKey(String userId) => 'profile_photo_path_$userId';

  /// Kunci Hive untuk tim favorit (kode klub, mis. `ARS`).
  ///
  /// Format: `favorite_team_<userId>`. Nilai legacy tanpa sufiks
  /// (`favorite_team`) diadopsi lewat [readUserScopedValue].
  static String favoriteTeamKey(String userId) => 'favorite_team_$userId';

  /// Kunci Hive untuk anggaran away day dalam Rupiah.
  ///
  /// Format: `away_day_budget_idr_<userId>`, disimpan sebagai teks hasil
  /// `double.toString()` (bisa berdesimal), bukan integer murni.
  static String awayDayBudgetKey(String userId) =>
      'away_day_budget_idr_$userId';

  /// Kunci penanda "preferensi belum tersinkron ke cloud".
  ///
  /// Format: `prefs_pending_<userId>`, nilainya string `'true'`. Disisipkan
  /// saat [saveDisplayName]/[saveProfilePrefs] gagal menulis metadata
  /// Supabase, dan dihapus setelah [retryPendingPrefs] berhasil.
  static String prefsPendingKey(String userId) => 'prefs_pending_$userId';

  /// Alias lama dari [prefsPendingKey] (dipakai saat nama tampilan gagal
  /// disimpan). Keduanya menunjuk kunci yang sama: `prefs_pending_<userId>`.
  static String displayNamePendingKey(String userId) => prefsPendingKey(userId);

  /// Bentuk kunci per-pengguna dari [base], atau null bila belum ada user id.
  ///
  /// Dipakai untuk nilai yang tidak punya helper statis (mis. key
  /// `pundit_<userId>`), sehingga semua data pengguna memakai pola sufiks
  /// yang sama dan bisa dibersihkan seragam saat logout.
  String? userScopedKey(String base) {
    final userId = currentUserId;
    return userId == null ? null : '${base}_$userId';
  }

  /// Reads a scoped value and migrates its legacy global value on first use.
  ///
  /// Membaca kunci ber-sufiks `base_<userId>`; kalau belum ada, nilai lama
  /// global `base` (ditulis versi aplikasi sebelumnya) dipakai lalu
  /// dipindahkan ke kunci ber-sufiks di latar belakang (fire-and-forget),
  /// dan kunci global dihapus supaya tidak bocor ke akun lain.
  ///
  /// Kunci legacy yang dikenal: `profile_display_name`, `profile_photo_path`,
  /// `favorite_team`, dan `away_day_budget_idr`. Kunci global lain ikut
  /// dimigrasi karena mekanismenya generik.
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

  /// Tulis nilai ke kunci per-pengguna `base_<userId>` di Hive box `app_cache`.
  ///
  /// Diam-diam diabaikan bila belum ada user id (belum masuk), supaya
  /// pemanggil tidak perlu mengecek login dulu.
  Future<void> writeUserScopedValue(String base, String value) async {
    final key = userScopedKey(base);
    if (key != null) await identityStore.put(key, value);
  }

  /// Masuk dengan email dan password lewat Supabase Auth.
  ///
  /// Email di-trim dan divalidasi kosong lebih dulu; password tidak diubah.
  /// Kegagalan apa pun dibungkus jadi [AuthException] berbahasa Indonesia
  /// (lihat [describeAuthError]). Melempar [notConfiguredAuthMessage] bila
  /// Supabase belum dikonfigurasi (mode mock).
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
  ///
  /// False juga bila Supabase belum dikonfigurasi (mode mock), sehingga
  /// layar kunci/biometrik tidak pernah membuka sesi yang tidak ada.
  Future<bool> hasSession() async {
    if (!_usesSupabase) return false;
    final session = supa.Supabase.instance.client.auth.currentSession;
    return session != null && !session.isExpired;
  }

  /// True bila perangkat mendukung biometrik dan ada biometrik yang
  /// terdaftar. Punya perangkat yang mendukung saja tidak cukup: enrolling
  /// biometrik di perangkat tetap dibutuhkan.
  Future<bool> canUseBiometric() async =>
      await _localAuth.isDeviceSupported() &&
      await _localAuth.canCheckBiometrics;

  /// Email user yang sedang masuk, atau null bila belum masuk / Supabase
  /// belum dikonfigurasi.
  Future<String?> userEmail() async {
    if (!_usesSupabase) return null;
    return supa.Supabase.instance.client.auth.currentUser?.email;
  }

  /// Simpan nama tampilan ke metadata Supabase dan tandai kegagalan untuk retry.
  ///
  /// Key metadata: `display_name`. Mengembalikan true bila berhasil; false
  /// bila Supabase tidak siap atau request gagal — pada kasus gagal penanda
  /// `prefs_pending_<userId>` ditulis supaya [retryPendingPrefs] mencoba lagi.
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

  /// Simpan tim favorit dan/atau anggaran away day ke metadata Supabase.
  ///
  /// Key metadata: `favorite_team` (kode klub) dan `away_day_budget_idr`
  /// (integer Rupiah, dibulatkan dari nilai desimal). Argumen null berarti
  /// "jangan sentuh field ini", jadi pemanggilan dengan keduanya null
  /// tidak melakukan request sama sekali dan mengembalikan true.
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

  /// Kirim ulang preferensi yang masih tertunda ke metadata Supabase.
  ///
  /// Dijalankan saat start berikutnya setelah sesi aktif. Sumber nilai tetap
  /// Hive box `app_cache`: `profile_display_name_<userId>`,
  /// `favorite_team_<userId>`, dan `away_day_budget_idr_<userId>`.
  /// Penanda `prefs_pending_<userId>` dihapus setelah berhasil; kalau gagal
  /// penanda sengaja disimpan untuk percobaan berikutnya.
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

  /// Alias lama [retryPendingPrefs] yang dipanggil saat nama tampilan gagal
  /// disimpan; keduanya menulis ulang metadata yang sama.
  Future<void> retryPendingDisplayName() => retryPendingPrefs();

  /// Tulis metadata user dengan menyalin metadata lama lalu menimpa field
  /// yang ada di [updates].
  ///
  /// Menyalin dulu (bukan menimpa penuh) supaya field metadata lain milik
  /// pengguna tidak ikut terhapus. Memakai hook injeksi bila ada, jika tidak
  /// memanggil `updateUser` milik Supabase.
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

  /// Metadata user saat ini (dict kosong bila tidak ada user atau metadata).
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

  /// Tim favorit dari metadata cloud (key `favorite_team`), atau null.
  String? cloudFavoriteTeam() => _cloudString('favorite_team');

  /// Anggaran away day dari metadata cloud (key `away_day_budget_idr`) dalam
  /// Rupiah bulat, atau null bila belum diisi.
  ///
  /// Nilai metadata bisa berupa angka desimal atau teks; keduanya dibaca,
  /// dan angka desimal dibulatkan ke integer terdekat.
  int? cloudBudgetIdr() {
    if (!_usesSupabase) return null;
    final meta = _currentUserMetadata();
    final value = meta['away_day_budget_idr'];
    return value is num ? value.round() : int.tryParse('$value');
  }

  /// Ambil nilai string dari metadata cloud, null bila kosong/tipe lain.
  String? _cloudString(String key) {
    if (!_usesSupabase) return null;
    final meta = _currentUserMetadata();
    final value = meta[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Token JWT Supabase untuk endpoint yang butuh Authorization header.
  ///
  /// Token diambil dari sesi Supabase yang aktif (bukan disimpan sendiri di
  /// secure storage), jadi null berarti belum masuk. Perlu diperbarui kalau
  /// sesi diperpanjang; pemanggil yang melakukan request ke server memakai
  /// nilai ini sebagai header `Authorization: Bearer <token>`.
  Future<String?> currentToken() async {
    if (!_usesSupabase) return null;
    return supa.Supabase.instance.client.auth.currentSession?.accessToken;
  }

  /// Biometrik hanya valid jika sudah pernah login (sesi Supabase ada).
  ///
  /// Melempar [AuthException] bila belum pernah login manual, biometrik tidak
  /// tersedia di perangkat, atau pengguna menolak/membatalkan sidik jari.
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
  ///
  /// Dua hal yang dibersihkan di sini: sesi Supabase (dicabut dari server
  /// bila bisa; kalau gagal, sesi lokal tetap dihapus oleh SDK) dan kunci
  /// privat dompet `wallet_private_key` di flutter_secure_storage.
  /// Identitas pemilik data lokal (`last_user_id`) sengaja TIDAK dihapus di
  /// sini supaya pergantian akun masih bisa dideteksi.
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
  ///
  /// Hanya satu kunci (`wallet_private_key`); dihapus saat logout supaya
  /// akun berikutnya tidak memakai dompet milik akun lama.
  static const privateKeyKeys = ['wallet_private_key'];

  /// Semua kunci Hive yang berisi data pengguna (U4).
  ///
  /// `away_day_expenses`, `passport_chain`, dan `score_predictions` juga
  /// adalah koleksi yang ikut disinkronkan (lihat `OfflineSyncDatabase`:
  /// tabel `sync_documents` dan `sync_deletions`), jadi menghapusnya di sini
  /// ikut menghapus salinan sinkronnya.
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
  ///
  /// Semua kunci yang diawali `pundit_` ikut terhapus saat logout, termasuk
  /// riwayat chat per klub (`pundit_chat_<clubKey>`).
  static const userKeyPrefixes = <String>['pundit_'];
}

/// Repository autentikasi bersama untuk seluruh aplikasi.
///
/// Memakai [secureStorageProvider] untuk kunci privat dompet dan
/// [LocalAuthentication] untuk biometrik perangkat.
final authRepositoryProvider = Provider((ref) => AuthRepository(
      ref.watch(secureStorageProvider),
      LocalAuthentication(),
    ));
