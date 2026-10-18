import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../prediction/providers/prediction_provider.dart';
import '../data/auth_repository.dart';
import 'auth_provider.dart';

/// Hapus seluruh data pengguna yang tersimpan di Hive (U4).
///
/// Dipisah dari provider supaya bisa dipanggil dari mana saja yang sedang
/// mengakhiri sesi, termasuk setelah sinkronisasi menerima 401. Kunci
/// non-pengguna seperti tema dan alasan penolakan izin tidak ikut terhapus.
Future<void> clearUserData() async {
  await HiveService.cache.deleteAll(AuthRepository.userDataKeys);
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
  ref
    ..invalidate(awayDayProvider)
    ..invalidate(awayDayBudgetProvider)
    ..invalidate(predictionsProvider)
    ..invalidate(chainProvider)
    // Alamat wallet ikut terbuang karena private key-nya dihapus saat logout.
    ..invalidate(walletAddressProvider);
  invalidateIdentityProviders(ref);
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
