import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../prediction/providers/prediction_provider.dart';
import '../data/auth_repository.dart';
import '../data/identity_store.dart';
import 'auth_provider.dart';

/// Kunci Hive pemilik data lokal di perangkat ini (user id Supabase).
///
/// Sengaja BUKAN bagian dari [AuthRepository.userDataKeys] dan tidak ikut
/// terhapus saat logout: identifikasi pemilik harus bertahan lintas sesi supaya
/// login akun berikutnya bisa mendeteksi pergantian akun.
const dataOwnerIdKey = 'last_user_id';

/// Kunci identitas/prefs legacy TANPA sufiks user (tulisan versi lama).
///
/// `readUserScopedValue` mengadopsinya ke akun mana pun yang login berikutnya,
/// jadi kunci global yang tertinggal = kebocoran lintas akun. Dihapus bersama
/// logout (U4) maupun saat ganti akun.
const legacyIdentityKeys = <String>[
  'profile_display_name',
  'profile_photo_path',
  'favorite_team',
  'away_day_budget_idr',
];

String? readDataOwnerId(IdentityStore store) => store.get(dataOwnerIdKey);

Future<void> writeDataOwnerId(IdentityStore store, String userId) =>
    store.put(dataOwnerIdKey, userId);

/// Hapus seluruh data pengguna yang tersimpan di Hive (U4).
///
/// Dipisah dari provider supaya bisa dipanggil dari mana saja yang sedang
/// mengakhiri sesi, termasuk setelah sinkronisasi menerima 401. Kunci
/// non-pengguna seperti tema dan alasan penolakan izin tidak ikut terhapus.
Future<void> clearUserData() async {
  await HiveService.cache.deleteAll(AuthRepository.userDataKeys);
  await HiveService.cache.deleteAll(legacyIdentityKeys);
  final prefixed = HiveService.cache.keys
      .where((k) => AuthRepository.userKeyPrefixes.any(k.startsWith))
      .toList();
  await HiveService.cache.deleteAll(prefixed);
}

/// Buang provider yang masih menyimpan data pengguna lama di memori (U4).
///
/// Hive sudah kosong, tapi notifier yang sudah dibuat masih memegang daftar
/// lama. Tanpa invalidate, pengguna berikutnya yang masuk di perangkat ini bisa
/// melihat data akun sebelumnya sebelum memuat ulang apa pun.
void invalidateUserDataProviders(Ref ref) {
  invalidateUserContentProviders(ref);
  invalidateIdentityProviders(ref);
}

/// Provider data konten (pengeluaran, prediksi, rantai, wallet) tanpa
/// identitas. Dipakai saat ganti akun di dalam `AsyncValue.guard` login:
/// invalidasi identitas tetap menjadi tugas `_afterIdentitySuccess` supaya
/// login akun yang sama tidak memicu gelombang invalidasi identitas ganda.
void invalidateUserContentProviders(Ref ref) {
  ref
    ..invalidate(awayDayProvider)
    ..invalidate(awayDayBudgetProvider)
    ..invalidate(predictionsProvider)
    ..invalidate(chainProvider)
    // Alamat wallet ikut terbuang karena private key-nya dihapus saat logout.
    ..invalidate(walletAddressProvider);
}

void invalidateIdentityProviders(Ref ref) {
  ref
    ..invalidate(sessionProvider)
    ..invalidate(userEmailProvider)
    ..invalidate(displayNameProvider)
    ..invalidate(effectiveDisplayNameProvider)
    ..invalidate(profilePhotoProvider)
    ..invalidate(favoriteKeyProvider)
    ..invalidate(awayDayBudgetProvider);
}
