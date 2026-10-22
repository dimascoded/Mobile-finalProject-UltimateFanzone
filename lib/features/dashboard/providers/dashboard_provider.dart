import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sync/providers/sync_provider.dart';

/// Indeks tab aktif Bottom Navigation.
///
/// StateProvider biasa (bukan `autoDispose`) karena dipakai seluruh
/// Dashboard; di-reset ke 0 (tab beranda) oleh [logoutProvider] saat keluar.
/// Tanpa efek samping penyimpanan.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Logout: hapus token, bersihkan data pengguna, reset state yang tersisa.
///
/// [AuthNotifier.logout] sudah menghapus isi Hive; invalidate di sini membuang
/// foto profil dan nama tampilan yang masih tertahan di memori notifier (U4).
///
/// Efek samping: sesi Supabase dicabut dan kunci secure storage
/// `wallet_private_key` dihapus; data pengguna di Hive `app_cache` (kunci
/// `away_day_expenses`, `score_predictions`, `passport_chain`,
/// `notified_results`, `penalty_block_day`, `last_sync_at`, dan kunci
/// berawalan `pundit_`) beserta baris SQLite `sync_documents` dan
/// `sync_deletions` dikosongkan; provider foto/nama/sinkronisasi di-invalidate
/// dan tab kembali ke 0. Kunci `last_user_id` tetap ada untuk deteksi
/// pergantian akun.
final logoutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(authProvider.notifier).logout();
    ref
      ..invalidate(profilePhotoProvider)
      ..invalidate(displayNameProvider)
      ..invalidate(effectiveDisplayNameProvider)
      ..invalidate(syncProvider)
      ..read(tabIndexProvider.notifier).state = 0;
  };
});

// ---------- Foto profil ----------

/// Notifier path file foto profil pengguna.
///
/// State-nya `String?` berisi path absolut file foto, atau null bila belum
/// ada / filenya sudah tidak ada. Path disimpan di Hive `app_cache` dengan
/// kunci per pengguna `profile_photo_path_<userId>` (dibaca lewat
/// [AuthRepository.readUserScopedValue], yang juga mengadopsi kunci legacy
/// global `profile_photo_path`). File gambarnya sendiri ada di folder
/// dokumen aplikasi.
///
/// Aturan §3.5: notifier ini bukan `autoDispose`, jadi kewajiban memeriksa
/// `mounted` setelah `await` tidak berlaku. [pick] menyentuh `state` hanya
/// sekali, sesudah file foto selesai disalin.
class ProfilePhotoNotifier extends StateNotifier<String?> {
  ProfilePhotoNotifier(this._repo, this._fileExists) : super(null) {
    unawaited(reload());
  }

  final AuthRepository _repo;
  final bool Function(String path) _fileExists;
  final _picker = ImagePicker();

  /// Muat ulang path foto dari penyimpanan per pengguna.
  ///
  /// State di-set null bila tidak ada sesi, atau bila path yang tersimpan
  /// menunjuk ke file yang sudah tidak ada. Tanpa efek samping selain
  /// pembaruan state.
  Future<void> reload() async {
    final userId = _repo.currentUserId;
    if (userId == null) {
      state = null;
      return;
    }
    final path = _repo.readUserScopedValue('profile_photo_path');
    state = path != null && _fileExists(path) ? path : null;
  }

  /// Pilih foto dari [source], salin ke folder permanen, lalu simpan pathnya.
  ///
  /// Foto dari image picker berada di cache sementara, jadi file disalin ke
  /// folder dokumen aplikasi dengan nama unik. Efek samping: menulis Hive
  /// `app_cache` (kunci `profile_photo_path_<userId>`), membuat satu file
  /// gambar baru, dan menghapus file lama bila ada. Tanpa verifikasi ke cloud.
  Future<void> pick(ImageSource source) async {
    final userId = _repo.currentUserId;
    if (userId == null) return;
    final x = await _picker.pickImage(
        source: source, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    // Salin ke folder permanen (file picker berada di cache sementara).
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    final old = state;
    state = dest;
    await _repo.writeUserScopedValue('profile_photo_path', dest);
    if (old != null && File(old).existsSync()) await File(old).delete();
  }
}

/// Fungsi untuk mengecek keberadaan file di disk.
///
/// Disuntikkan ke [ProfilePhotoNotifier] agar bisa diuji tanpa sistem file
/// sungguhan. Tanpa efek samping.
final profilePhotoFileExistsProvider = Provider<bool Function(String path)>(
    (ref) => (path) => File(path).existsSync());

/// Path file foto profil milik pengguna aktif.
///
/// State-nya `String?`: path absolut file foto atau null bila belum ada.
/// Dihapus saat logout lewat [logoutProvider] (invalidate provider ini).
/// Tanpa efek samping.
final profilePhotoProvider =
    StateNotifierProvider<ProfilePhotoNotifier, String?>(
        (ref) => ProfilePhotoNotifier(
              ref.watch(authRepositoryProvider),
              ref.watch(profilePhotoFileExistsProvider),
            ));

// ---------- Nama tampilan ----------
/// Kunci Hive penyimpan nama tampilan lokal.
const displayNameHiveKey = 'profile_display_name';

/// Kunci Hive per pengguna untuk nama tampilan.
///
/// Dihasilkan dari [AuthRepository.displayNameKey] agar konsisten dengan
/// seluruh penyimpanan per pengguna lain.
String displayNameHiveKeyFor(String userId) =>
    AuthRepository.displayNameKey(userId);

/// Validasi nama tampilan. Mengembalikan pesan galat Bahasa Indonesia, atau
/// null bila valid. Input dibersihkan dulu: whitespace di-trim dan spasi
/// berturut-turut dijadikan satu spasi.
String? validateDisplayName(String raw) {
  final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.length < 2) return 'Nama minimal 2 karakter';
  if (cleaned.length > 30) return 'Nama maksimal 30 karakter';
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(cleaned)) {
    return 'Nama tidak boleh mengandung karakter kontrol';
  }
  return null;
}

/// Simpan nama tampilan: lokal (Hive) selalu dulu, lalu best-effort ke
/// metadata Supabase supaya selamat saat logout/masuk ulang.
///
/// State-nya `String?` berisi nama tampilan tersimpan, atau null bila belum
/// pernah diatur. Nilai awal diambil dari Hive per pengguna
/// (`profile_display_name_<userId>`).
///
/// Aturan §3.5: notifier ini bukan `autoDispose`, jadi kewajiban memeriksa
/// `mounted` setelah `await` tidak berlaku. [set] juga menyentuh `state`
/// sebelum `await` pertama, sehingga tidak ada state usang yang ditulis
/// setelah request cloud selesai.
class DisplayNameNotifier extends StateNotifier<String?> {
  DisplayNameNotifier(this._repo) : super(_readForUser(_repo));
  final AuthRepository _repo;

  static String? _readForUser(AuthRepository repo) {
    return repo.readUserScopedValue(displayNameHiveKey);
  }

  /// Validasi [raw]; bila valid simpan ke Hive + state lalu simpan ke cloud
  /// (fire-and-forget). Mengembalikan pesan galat, atau null bila berhasil.
  ///
  /// Efek samping: menulis Hive `app_cache` (kunci
  /// `profile_display_name_<userId>`) lalu mencoba menyimpan metadata
  /// `display_name` ke Supabase. Bila simpan ke cloud gagal, nama tetap
  /// tersimpan lokal dan fungsi mengembalikan pesan peringatan.
  Future<String?> set(String raw) async {
    final error = validateDisplayName(raw);
    if (error != null) return error;
    final userId = _repo.currentUserId;
    if (userId == null) return 'Sesi tidak ditemukan. Masuk ulang.';
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    state = cleaned;
    await _repo.writeUserScopedValue(displayNameHiveKey, cleaned);
    if (!await _repo.saveDisplayName(cleaned)) {
      return 'Nama tersimpan di perangkat, tetapi belum tersimpan ke akun. Coba lagi nanti.';
    }
    return null;
  }
}

/// Nama tampilan yang disimpan pengguna di perangkat ini.
///
/// State-nya `String?`; null berarti belum pernah diatur. Dihapus saat logout
/// lewat [logoutProvider] (invalidate provider ini).
final displayNameProvider = StateNotifierProvider<DisplayNameNotifier, String?>(
    (ref) => DisplayNameNotifier(ref.watch(authRepositoryProvider)));

/// Nama yang ditampilkan ke pengguna. Urutan resolusi:
///   1. nama lokal (hasil edit pengguna),
///   2. nama dari metadata Supabase (disalin ke Hive sekali),
///   3. nama yang diturunkan dari email,
///   4. 'Profil saya'.
///
/// `FutureProvider`: bisa perlu `await` saat metadata cloud dibaca. Efek
/// samping: nama dari cloud disalin sekali ke Hive `app_cache` (kunci
/// `profile_display_name_<userId>`) supaya start berikutnya langsung lokal.
final effectiveDisplayNameProvider = FutureProvider<String>((ref) async {
  final repo = ref.watch(authRepositoryProvider);
  final local = ref.watch(displayNameProvider);
  if (local != null && local.isNotEmpty) return local;

  String? cloud;
  try {
    cloud = repo.cloudDisplayName();
  } catch (_) {
    cloud = null;
  }
  if (cloud != null && cloud.isNotEmpty) {
    // Salin sekali ke Hive supaya start berikutnya langsung lokal.
    final userId = repo.currentUserId;
    if (userId != null) {
      await repo.writeUserScopedValue(displayNameHiveKey, cloud);
    }
    return cloud;
  }

  final email = await ref.watch(userEmailProvider.future);
  final derived =
      email?.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ').trim() ?? '';
  return derived.isEmpty ? 'Profil saya' : derived;
});
