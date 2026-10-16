import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/network/rates_provider.dart';
import 'package:ultimate_fanzone/features/away_day/presentation/away_day_screen.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';

PlClub _club(String key, String name, String tla) => PlClub(
      key: key,
      name: name,
      shortName: name,
      tla: tla,
      city: 'Kota',
      stadium: 'Stadion $name',
      lat: 0,
      lng: 0,
      color: 0xFFEF0107,
      aliases: [name],
    );

/// Repositori klub palsu yang mengembalikan kunci favorit buatan.
class _FakeClubRepository extends ClubRepository {
  _FakeClubRepository(this.key);

  final String key;

  @override
  String? favoriteKey() => key;
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_away_add');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('app_cache_away_add');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('membuka form Catat tidak memicu error layout', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clubs = <PlClub>[
      _club('arsenal', 'Arsenal', 'ARS'),
      _club('chelsea', 'Chelsea', 'CHE'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clubsProvider.overrideWith((ref) async => clubs),
          clubCrestProvider.overrideWithValue(const <String, String>{}),
          favoriteKeyProvider.overrideWith(
            (ref) => FavoriteTeamNotifier(_FakeClubRepository('tidak-ada')),
          ),
          ratesProvider.overrideWith(
            (ref) async => RatesSnapshot(
              const {'GBP': 0.00005, 'USD': 0.00004, 'EUR': 0.000046},
              DateTime.now(),
            ),
          ),
          worldClockProvider.overrideWith((ref) async* {
            final now = DateTime.utc(2026, 1, 1, 12);
            yield {
              'UTC': now,
              'WIB': now,
              'WITA': now,
              'WIT': now,
              'London': now,
            };
          }),
        ],
        child: const MaterialApp(home: AwayDayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Catat'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
