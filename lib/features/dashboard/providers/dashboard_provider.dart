import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/database/hive_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../sync/providers/sync_provider.dart';

/// Indeks tab aktif Bottom Navigation.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Logout: hapus token, bersihkan data pengguna, reset state yang tersisa.
///
/// [AuthNotifier.logout] sudah menghapus isi Hive; invalidate di sini membuang
/// foto profil yang masih tertahan di memori notifier (U4).
final logoutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(authProvider.notifier).logout();
    ref
      ..invalidate(profilePhotoProvider)
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
