import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/auth/providers/auth_provider.dart';
import 'package:ultimate_fanzone/features/auth/providers/user_data_cleanup.dart';

/// U4: setelah logout, data pengguna tidak boleh tersisa di perangkat.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_user_data');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('app_cache_test');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('data pengguna dihapus, prefs perangkat tetap ada', () async {
    final box = HiveService.cache;
    await box.putAll({
      'away_day_expenses': '[{"title":"Tiket"}]',
      AuthRepository.awayDayBudgetKey('user-a'): '500000',
      'score_predictions': '[{"matchId":1}]',
      'passport_chain': '[]',
      AuthRepository.profilePhotoKey('user-a'): '/tmp/foto.jpg',
      'notified_results': '[7001]',
      'penalty_block_day': '2026-08-15',
      'last_sync_at': '1700000000000',
      AuthRepository.favoriteTeamKey('user-a'): 'arsenal',
      'pundit_arsenal': 'teks',
      'pundit_chelsea_at': '2026-08-15T00:00:00Z',
      // Prefs perangkat, bukan data pengguna.
      'theme_mode': 'dark',
      'permission_rationale': '["location"]',
      'fd_matches': '{}',
    });

    await clearUserData();

    // Semua data pengguna hilang, termasuk cache Pundit per klub.
    for (final key in [
      'away_day_expenses',
      'score_predictions',
      'passport_chain',
      'notified_results',
      'penalty_block_day',
      'last_sync_at',
      'pundit_arsenal',
      'pundit_chelsea_at',
    ]) {
      expect(box.get(key), isNull, reason: '$key seharusnya terhapus');
    }
    expect(box.get(AuthRepository.awayDayBudgetKey('user-a')), '500000');
    expect(box.get(AuthRepository.profilePhotoKey('user-a')), '/tmp/foto.jpg');
    expect(box.get(AuthRepository.favoriteTeamKey('user-a')), 'arsenal');

    // Prefs perangkat tetap utuh.
    expect(box.get('theme_mode'), 'dark');
    expect(box.get('permission_rationale'), '["location"]');
    expect(box.get('fd_matches'), '{}');
  });

  test('daftar kunci yang dipakai logout lengkap', () {
    // Kunci yang ada di repository tapi tidak ada di userDataKeys akan bocor.
    expect(AuthRepository.userDataKeys, isNotEmpty);
    expect(AuthRepository.privateKeyKeys, contains('wallet_private_key'));
  });

  test(
      'preferensi biometrik tersimpan dan tidak dihapus saat data akun dibersihkan',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(biometricEnabledProvider), isTrue);
    await container.read(biometricEnabledProvider.notifier).setEnabled(false);
    expect(HiveService.cache.get('biometric_enabled'), 'false');

    await clearUserData();

    expect(HiveService.cache.get('biometric_enabled'), 'false');
  });
}
