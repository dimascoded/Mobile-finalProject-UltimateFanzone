import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:premiere_league_fan_assistant/core/database/hive_service.dart';
import 'package:premiere_league_fan_assistant/features/auth/providers/user_data_cleanup.dart';
import 'package:premiere_league_fan_assistant/features/away_day/data/away_day_repository.dart';
import 'package:premiere_league_fan_assistant/features/away_day/providers/away_day_providers.dart';

/// U4: data yang masih tertahan di memori provider harus ikut hilang setelah
/// akun keluar, bukan hanya yang ada di Hive.
/// `invalidateUserDataProviders` butuh [Ref], yang hanya ada di dalam callback
/// provider. Tester ini membungkusnya agar bisa dipanggil dari test.
final invalidateFromTest = Provider<void>((ref) {
  invalidateUserDataProviders(ref);
});

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_logout');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('app_cache_logout');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('logout membuat provider memuat ulang data yang kosong', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Data pengguna A sudah masuk Hive dan dimuat ke memori.
    await container.read(awayDayProvider.notifier).add(
          title: 'Tiket Arsenal',
          amountGbp: 60,
          amountIdr: 1200000,
          category: AwayDayCategory.tiket,
        );
    expect(container.read(awayDayProvider), hasLength(1));
    expect(HiveService.cache.get('away_day_expenses'), isNotNull);

    await clearUserData();
    container.read(invalidateFromTest);

    // Provider yang sudah dibuang memuat ulang dari Hive yang sekarang kosong.
    expect(container.read(awayDayProvider), isEmpty);
  });
}
