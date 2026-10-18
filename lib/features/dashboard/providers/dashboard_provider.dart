import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/database/hive_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sync/providers/sync_provider.dart';

/// Indeks tab aktif Bottom Navigation.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Logout: hapus token, bersihkan data pengguna, reset state yang tersisa.
///
/// [AuthNotifier.logout] sudah menghapus isi Hive; invalidate di sini membuang
/// foto profil dan nama tampilan yang masih tertahan di memori notifier (U4).
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
class ProfilePhotoNotifier extends StateNotifier<String?> {
  ProfilePhotoNotifier() : super(HiveService.cache.get(_key));
  static const _key = 'profile_photo_path';
  final _picker = ImagePicker();

  Future<void> pick(ImageSource source) async {
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
    await HiveService.cache.put(_key, dest);
    if (old != null && File(old).existsSync()) await File(old).delete();
  }
}

final profilePhotoProvider =
    StateNotifierProvider<ProfilePhotoNotifier, String?>(
        (ref) => ProfilePhotoNotifier());

// ---------- Nama tampilan ----------
/// Kunci Hive penyimpan nama tampilan lokal.
const displayNameHiveKey = 'profile_display_name';

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
class DisplayNameNotifier extends StateNotifier<String?> {
  DisplayNameNotifier(this._repo) : super(HiveService.cache.get(_key));
  static const _key = displayNameHiveKey;
  final AuthRepository _repo;

  /// Validasi [raw]; bila valid simpan ke Hive + state lalu simpan ke cloud
  /// (fire-and-forget). Mengembalikan pesan galat, atau null bila berhasil.
  Future<String?> set(String raw) async {
    final error = validateDisplayName(raw);
    if (error != null) return error;
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    state = cleaned;
    await HiveService.cache.put(_key, cleaned);
    unawaited(_repo.saveDisplayName(cleaned));
    return null;
  }
}

final displayNameProvider =
    StateNotifierProvider<DisplayNameNotifier, String?>(
        (ref) => DisplayNameNotifier(ref.watch(authRepositoryProvider)));

/// Nama yang ditampilkan ke pengguna. Urutan resolusi:
///   1. nama lokal (hasil edit pengguna),
///   2. nama dari metadata Supabase (disalin ke Hive sekali),
///   3. nama yang diturunkan dari email,
///   4. 'Profil saya'.
final effectiveDisplayNameProvider = FutureProvider<String>((ref) async {
  final local = ref.watch(displayNameProvider);
  if (local != null && local.isNotEmpty) return local;

  final repo = ref.watch(authRepositoryProvider);
  String? cloud;
  try {
    cloud = repo.cloudDisplayName();
  } catch (_) {
    cloud = null;
  }
  if (cloud != null && cloud.isNotEmpty) {
    // Salin sekali ke Hive supaya start berikutnya langsung lokal.
    await HiveService.cache.put(displayNameHiveKey, cloud);
    return cloud;
  }

  final email = await ref.watch(userEmailProvider.future);
  final derived = email
          ?.split('@')
          .first
          .replaceAll(RegExp(r'[._-]+'), ' ')
          .trim() ??
      '';
  return derived.isEmpty ? 'Profil saya' : derived;
});
