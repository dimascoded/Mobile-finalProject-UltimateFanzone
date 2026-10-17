import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/network/rates_provider.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/away_day/presentation/away_day_screen.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/presentation/match_center_screen.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/lens/presentation/lens_screen.dart';
import 'package:ultimate_fanzone/features/prediction/presentation/prediction_screen.dart';
import 'package:ultimate_fanzone/features/pundit/presentation/pundit_screen.dart';
import 'package:ultimate_fanzone/features/stadium_pointer/presentation/stadium_pointer_screen.dart';

/// Repositori klub dalam memori: tidak menyentuh Hive milik perangkat.
class _InMemoryClubRepository extends ClubRepository {
  _InMemoryClubRepository(this._favoriteKey);

  final String? _favoriteKey;

  @override
  String? favoriteKey() => _favoriteKey;
}

final _clubs = <PlClub>[
  const PlClub(
    key: 'arsenal',
    name: 'Arsenal',
    shortName: 'Arsenal',
    tla: 'ARS',
    city: 'London',
    stadium: 'Emirates Stadium',
    lat: 51.5549,
    lng: -0.1084,
    color: 0xFFEF0107,
    aliases: ['arsenal'],
  ),
  const PlClub(
    key: 'chelsea',
    name: 'Chelsea',
    shortName: 'Chelsea',
    tla: 'CHE',
    city: 'London',
    stadium: 'Stamford Bridge',
    lat: 51.4817,
    lng: -0.191,
    color: 0xFF034694,
    aliases: ['chelsea'],
  ),
];

final _matches = <FootballMatch>[
  FootballMatch(
    id: 1,
    kickoffUtc: DateTime.utc(2030, 1, 1, 20),
    status: 'SCHEDULED',
    matchday: 1,
    homeName: 'Arsenal',
    awayName: 'Chelsea',
    homeShort: 'ARS',
    awayShort: 'CHE',
    homeTla: 'ARS',
    awayTla: 'CHE',
  ),
  FootballMatch(
    id: 2,
    kickoffUtc: DateTime.utc(2030, 1, 2, 20),
    status: 'FINISHED',
    matchday: 1,
    homeName: 'Chelsea',
    awayName: 'Arsenal',
    homeShort: 'CHE',
    awayShort: 'ARS',
    homeTla: 'CHE',
    awayTla: 'ARS',
    homeScore: 1,
    awayScore: 2,
  ),
];

final _matchesResult = FootballResult<List<FootballMatch>>(
  _matches,
  DataSource.live,
  DateTime.utc(2030, 1, 1),
);

final _standingsResult = FootballResult<List<StandingRow>>(
  const [
    StandingRow(
      position: 1,
      teamName: 'Arsenal',
      teamShort: 'ARS',
      tla: 'ARS',
      played: 10,
      won: 8,
      draw: 1,
      lost: 1,
      goalDiff: 15,
      points: 25,
    ),
    StandingRow(
      position: 2,
      teamName: 'Chelsea',
      teamShort: 'CHE',
      tla: 'CHE',
      played: 10,
      won: 7,
      draw: 1,
      lost: 2,
      goalDiff: 10,
      points: 22,
    ),
  ],
  DataSource.live,
  DateTime.utc(2030, 1, 1),
);

final _scorersResult = FootballResult<List<ScorerRow>>(
  const [
    ScorerRow(
        player: 'Pemain A', teamName: 'Arsenal', teamShort: 'ARS', goals: 9),
    ScorerRow(
        player: 'Pemain B', teamName: 'Chelsea', teamShort: 'CHE', goals: 7),
  ],
  DataSource.live,
  DateTime.utc(2030, 1, 1),
);

List<Override> _overrides() => [
      matchesProvider.overrideWith((ref) async => _matchesResult),
      standingsProvider.overrideWith((ref) async => _standingsResult),
      scorersProvider.overrideWith((ref) async => _scorersResult),
      clubsProvider.overrideWith((ref) async => _clubs),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      favoriteClubProvider.overrideWithValue(null),
      favoriteKeyProvider.overrideWith(
        (ref) => FavoriteTeamNotifier(_InMemoryClubRepository(null)),
      ),
      clubRepositoryProvider.overrideWithValue(_InMemoryClubRepository(null)),
      ratesProvider.overrideWith(
        (ref) async => RatesSnapshot(
          const {'GBP': 0.00005, 'USD': 0.00004, 'EUR': 0.000046},
          DateTime.utc(2030, 1, 1),
        ),
      ),
      worldClockProvider.overrideWith((ref) async* {
        final now = DateTime.utc(2030, 1, 1, 12);
        yield {
          'UTC': now,
          'WIB': now,
          'WITA': now,
          'WIT': now,
          'London': now,
        };
      }),
    ];

Widget _app(WidgetTester tester, Widget screen, {required ThemeData theme}) =>
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: screen,
        ),
      ),
    );

ThemeData _theme(Brightness b) =>
    b == Brightness.light ? AppTheme.light : AppTheme.dark;

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_phase5b');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('phase5b_box');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final screens = <String, Widget>{
    'MatchCenterScreen': const MatchCenterScreen(),
    'PredictionScreen': const PredictionScreen(),
    'PunditScreen': const PunditScreen(),
    'LensScreen': const LensScreen(),
    'AwayDayScreen': const AwayDayScreen(),
  };

  for (final entry in screens.entries) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${entry.key} 320dp + textScaler 1.3 tanpa overflow '
        '(${brightness.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _app(tester, entry.value, theme: _theme(brightness)),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'CompassDialTestWrapper 320dp render tanpa error '
      '(${brightness.name})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(brightness),
            home: const Scaffold(
              body: CompassDialTestWrapper(
                relativeBearing: 42,
                color: Color(0xFFEF0107),
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey<String>('stadium-compass-dial')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('MatchCenterScreen menampilkan laga dan badge status',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(tester, const MatchCenterScreen(), theme: AppTheme.light),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pekan 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
