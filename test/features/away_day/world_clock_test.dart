import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/network/rates_provider.dart';
import 'package:ultimate_fanzone/core/utils/time_utils.dart';
import 'package:ultimate_fanzone/features/away_day/presentation/away_day_screen.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';

class _InMemoryClubRepository extends ClubRepository {
  _InMemoryClubRepository(this._favoriteKey);

  final String? _favoriteKey;

  @override
  String? favoriteKey() => _favoriteKey;
}

const _manCity = PlClub(
  key: 'mci',
  name: 'Manchester City',
  shortName: 'Man City',
  tla: 'MCI',
  city: 'Manchester',
  stadium: 'Etihad Stadium',
  lat: 53.4831,
  lng: -2.2004,
  color: 0xFF6CABDD,
  aliases: ['man city'],
);

final DateTime _now = DateTime.utc(2026, 6, 15, 12);

List<Override> _overrides({
  required PlClub? favorite,
  String? indoCity,
  String zone = 'WIB',
}) =>
    [
      worldClockProvider.overrideWith((ref) async* {
        yield <String, DateTime>{
          'WIB': TimeUtils.wib(_now),
          'WITA': TimeUtils.wita(_now),
          'WIT': TimeUtils.wit(_now),
          'London': TimeUtils.london(_now),
        };
      }),
      favoriteClubProvider.overrideWith((ref) => favorite),
      favoriteKeyProvider.overrideWith(
        (ref) => FavoriteTeamNotifier(_InMemoryClubRepository(favorite?.key)),
      ),
      awayDayClockZoneProvider.overrideWith((ref) => zone),
      awayDayClockIndoCityProvider.overrideWith((ref) => indoCity),
      ratesProvider.overrideWith(
        (ref) async => RatesSnapshot(
          const {'GBP': 0.00005, 'USD': 0.00004, 'EUR': 0.000046},
          _now,
        ),
      ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required PlClub? favorite,
  String? indoCity,
  String zone = 'WIB',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides:
          _overrides(favorite: favorite, indoCity: indoCity, zone: zone),
      child: const MaterialApp(home: AwayDayScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _readout(String suffix) => find.byKey(ValueKey('clock-readout-$suffix'));

bool _hasText(WidgetTester tester, String needle) {
  final lower = needle.toLowerCase();
  return tester
      .widgetList<Text>(find.byType(Text))
      .any((t) => (t.data ?? '').toLowerCase().contains(lower));
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('away_day_world_clock');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('cache');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('kota klub favorit tampil dengan jam London',
      (tester) async {
    await _pump(tester, favorite: _manCity);

    expect(
      find.descendant(of: _readout('london'), matching: find.text('Manchester')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _readout('london'),
        matching: find.text(TimeUtils.format(TimeUtils.london(_now))),
      ),
      findsOneWidget,
    );
    expect(find.text('Jam resmi Inggris (London)'), findsOneWidget);
    expect(find.textContaining('Klub favorit:'), findsNothing);
  });

  testWidgets('tanpa klub favorit memakai label London', (tester) async {
    await _pump(tester, favorite: null);

    expect(
      find.descendant(of: _readout('london'), matching: find.text('London')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _readout('london'),
        matching: find.text('Pilih klub favorit untuk memakai nama kotanya'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('kartu zona menampilkan WIB, WITA, WIT dari waktu UTC tetap',
      (tester) async {
    await _pump(tester, favorite: null, zone: 'WIB');

    final zone = _readout('zone');
    expect(
      find.descendant(of: zone, matching: find.text('WIB')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: zone,
        matching: find.text(TimeUtils.format(TimeUtils.wib(_now))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zone, matching: find.text('Waktu sipil Indonesia')),
      findsOneWidget,
    );
  });

  testWidgets('dropdown zona mengganti hanya kartu zona, bukan kartu kota',
      (tester) async {
    await _pump(tester, favorite: null, indoCity: 'Jakarta', zone: 'WIB');

    await tester.tap(find.byKey(const ValueKey('clock-zone-WIB')));
    await tester.pump();
    await tester.tap(find.text('WIT').last);
    await tester.pump(const Duration(milliseconds: 100));

    final zone = _readout('zone');
    expect(
      find.descendant(of: zone, matching: find.text('WIT')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: zone,
        matching: find.text(TimeUtils.format(TimeUtils.wit(_now))),
      ),
      findsOneWidget,
    );

    // Kartu kota tetap memakai zona kota itu sendiri (Jakarta = WIB).
    final city = _readout('indo-city');
    expect(
      find.descendant(of: city, matching: find.text('Jakarta')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: city,
        matching: find.text(TimeUtils.format(TimeUtils.wib(_now))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: city, matching: find.text('WIB')),
      findsOneWidget,
    );
  });

  testWidgets('kota Indonesia WIT tampil dengan namanya, jam WIT, zona WIT',
      (tester) async {
    await _pump(tester, favorite: null, indoCity: 'Jayapura');

    final city = _readout('indo-city');
    expect(
      find.descendant(of: city, matching: find.text('Jayapura')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: city,
        matching: find.text(TimeUtils.format(TimeUtils.wit(_now))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: city, matching: find.text('WIT')),
      findsOneWidget,
    );
  });

  testWidgets('pilih kota WIB mengubah kartu kota ke jam WIB', (tester) async {
    await _pump(tester, favorite: null, indoCity: 'Jayapura');

    await tester.tap(find.byKey(const ValueKey('clock-indo-Jayapura')));
    await tester.pump();
    await tester.tap(find.text('Jakarta').last);
    await tester.pump(const Duration(milliseconds: 100));

    final city = _readout('indo-city');
    expect(
      find.descendant(of: city, matching: find.text('Jakarta')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: city,
        matching: find.text(TimeUtils.format(TimeUtils.wib(_now))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: city, matching: find.text('WIB')),
      findsOneWidget,
    );
  });

  testWidgets('kartu hanya punya tiga readout tanpa surya/Selisih',
      (tester) async {
    await _pump(tester, favorite: _manCity);

    final readouts = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('clock-readout-'),
    );
    expect(readouts, findsNWidgets(3));
    expect(_hasText(tester, 'surya'), isFalse);
    expect(_hasText(tester, 'Selisih'), isFalse);
    expect(find.text('Zona waktu Indonesia'), findsOneWidget);
    expect(find.text('Kota di Indonesia'), findsOneWidget);
  });

  testWidgets('tanpa overflow pada lebar 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    await _pump(tester, favorite: _manCity, indoCity: 'Jayapura');

    expect(tester.takeException(), isNull);
    expect(_readout('zone'), findsOneWidget);
    expect(_readout('indo-city'), findsOneWidget);
    expect(_readout('london'), findsOneWidget);
  });
}
