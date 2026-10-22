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

/// Kontrak pembersihan data pengguna untuk seluruh aplikasi.
///
/// File ini adalah satu-satunya tempat yang tahu "data apa saja yang milik
/// pengguna" dan "provider mana yang harus dibuang setelah data itu dihapus".
/// Ada tiga operasi dan satu penanda:
///
/// 1. [clearUserData] — menghapus data pengguna yang tersimpan di Hive
///    `app_cache` (termasuk kunci berawalan `pundit_`).
/// 2. [invalidateUserDataProviders] — membuang provider yang masih menyimpan
///    data lama di memori, lalu memuat ulang provider identitas.
/// 3. [invalidateUserContentProviders] — membuang HANYA provider data konten
///    (tanpa identitas), dipakai saat ganti akun.
/// 4. Penanda pemilik data lokal: kunci Hive [dataOwnerIdKey]
///    (`last_user_id`) yang bertahan lintas sesi.
///
/// [invalidateIdentityProviders] menutup sisi identitasnya: sesi, email,
/// nama tampilan, foto profil, dan tim favorit ikut di-invalidate supaya
/// UI membaca nilai baru setelah login/logout/ganti akun.
///
/// Urutan pemakaian yang benar: hapus penyimpanan dulu
/// ([clearUserData]), baru invalidate provider
/// ([invalidateUserDataProviders] / [invalidateUserContentProviders]).
/// Membalik urutannya membuat provider memuat ulang data yang sudah dihapus
/// dan memunculkan data akun lama sesaat.

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

/// Baca id pemilik data lokal dari [store] (kunci `last_user_id`).
///
/// Fungsi murni: mengembalikan null bila belum pernah ada akun yang diklaim
/// sebagai pemilik data di perangkat ini.
String? readDataOwnerId(IdentityStore store) => store.get(dataOwnerIdKey);

/// Tulis id pemilik data lokal ke [store] (kunci `last_user_id`).
///
/// Efek samping: menulis ke Hive `app_cache` lewat [IdentityStore.put]. Nilai
/// ini bertahan lintas logout dan hanya ditulis ulang ketika sinkronisasi
/// atau login memastikan ulang pemilik yang sedang aktif.
Future<void> writeDataOwnerId(IdentityStore store, String userId) =>
    store.put(dataOwnerIdKey, userId);

/// Hapus seluruh data pengguna yang tersimpan di Hive (U4).
///
/// Dipisah dari provider supaya bisa dipanggil dari mana saja yang sedang
/// mengakhiri sesi, termasuk setelah sinkronisasi menerima 401. Kunci
/// non-pengguna seperti tema dan alasan penolakan izin tidak ikut terhapus.
///
/// Yang dihapus dari Hive `app_cache`:
///
/// - semua kunci di [AuthRepository.userDataKeys] (`away_day_expenses`,
///   `score_predictions`, `passport_chain`, `notified_results`,
///   `penalty_block_day`, `last_sync_at`);
/// - semua kunci legacy di [legacyIdentityKeys];
/// - semua kunci berawalan awalan di [AuthRepository.userKeyPrefixes]
///   (`pundit_`).
///
/// Yang SENGAJA tidak dihapus: [dataOwnerIdKey] (`last_user_id`),
/// `biometric_enabled`, `theme_mode`, `permission_rationale`, kunci cache
/// football-data.org (`fd_matches`, `fd_standings`, `fd_scorers` beserta
/// `_at`), `exchange_rates`, `kickoff_reminder_leads`,
/// `away_day_summary_currency`, dan `exact_alarm_asked` — semuanya bukan data
/// pribadi akun.
///
/// Efek samping: menulis ke Hive `app_cache` saja. Tabel SQLite
/// `sync_documents`/`sync_deletions` dikosongkan terpisah lewat
/// [OfflineSyncDatabase.clear].
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
///
/// Efek samping: provider konten dan identitas di-invalidate sehingga state
/// di memori dibuang dan dibaca ulang dari penyimpanan yang sudah bersih.
void invalidateUserDataProviders(Ref ref) {
  invalidateUserContentProviders(ref);
  invalidateIdentityProviders(ref);
}

/// Provider data konten (pengeluaran, prediksi, rantai, wallet) tanpa
/// identitas. Dipakai saat ganti akun di dalam `AsyncValue.guard` login:
/// invalidasi identitas tetap menjadi tugas `_afterIdentitySuccess` supaya
/// login akun yang sama tidak memicu gelombang invalidasi identitas ganda.
///
/// Efek samping: meng-invalidate [awayDayProvider], [awayDayBudgetProvider],
/// [predictionsProvider], [chainProvider], dan [walletAddressProvider]
/// sehingga isinya dimuat ulang dari penyimpanan yang sudah dibersihkan.
void invalidateUserContentProviders(Ref ref) {
  ref
    ..invalidate(awayDayProvider)
    ..invalidate(awayDayBudgetProvider)
    ..invalidate(predictionsProvider)
    ..invalidate(chainProvider)
    // Alamat wallet ikut terbuang karena private key-nya dihapus saat logout.
    ..invalidate(walletAddressProvider);
}

/// Buang provider yang menyimpan identitas sesi dan preferensi tampilan.
///
/// Dipanggil setelah login/logout/ganti akun supaya nama, foto, email, sesi,
/// dan tim favorit dibaca ulang sesuai akun yang aktif.
///
/// Efek samping: meng-invalidate [sessionProvider], [userEmailProvider],
/// [displayNameProvider], [effectiveDisplayNameProvider],
/// [profilePhotoProvider], [favoriteKeyProvider], dan
/// [awayDayBudgetProvider].
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
