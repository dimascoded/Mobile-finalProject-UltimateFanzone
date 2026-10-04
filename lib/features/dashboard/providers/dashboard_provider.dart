import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/database/hive_service.dart';
import '../../auth/providers/auth_provider.dart';

/// Indeks tab aktif Bottom Navigation.
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Logout: hapus token, reset indeks tab ke 0.
final logoutProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(authProvider.notifier).logout();
    ref.read(tabIndexProvider.notifier).state = 0;
  };
});

// ---------- Foto profil ----------
class ProfilePhotoNotifier extends StateNotifier<String?> {
  ProfilePhotoNotifier() : super(HiveService.cache.get(_key));
  static const _key = 'profile_photo_path';
  final _picker = ImagePicker();

  Future<void> pick(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (x == null) return;
    // Salin ke folder permanen (file picker berada di cache sementara).
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    final old = state;
    state = dest;
    await HiveService.cache.put(_key, dest);
    if (old != null && File(old).existsSync()) await File(old).delete();
  }
}

final profilePhotoProvider = StateNotifierProvider<ProfilePhotoNotifier, String?>(
    (ref) => ProfilePhotoNotifier());

// ---------- Saran & Kesan mata kuliah PAM ----------
class PamFeedback {
  const PamFeedback({this.kesan = '', this.saran = ''});
  final String kesan, saran;
  Map<String, dynamic> toJson() => {'kesan': kesan, 'saran': saran};
  factory PamFeedback.fromJson(Map<String, dynamic> j) =>
      PamFeedback(kesan: j['kesan'] ?? '', saran: j['saran'] ?? '');
}

class FeedbackNotifier extends StateNotifier<PamFeedback> {
  FeedbackNotifier() : super(_load());
  static const _key = 'pam_feedback';

  static PamFeedback _load() {
    final raw = HiveService.cache.get(_key);
    return raw == null
        ? const PamFeedback()
        : PamFeedback.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> save(String kesan, String saran) async {
    state = PamFeedback(kesan: kesan.trim(), saran: saran.trim());
    await HiveService.cache.put(_key, jsonEncode(state.toJson()));
  }
}

final feedbackProvider = StateNotifierProvider<FeedbackNotifier, PamFeedback>(
    (ref) => FeedbackNotifier());
