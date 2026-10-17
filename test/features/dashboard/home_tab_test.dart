import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/home_tab.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';
import 'package:ultimate_fanzone/features/gamification/providers/card_collection_provider.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';

/// Anggaran tanpa menyentuh Hive: cukup untuk menguji widget Home.
class _FakeAwayRepo extends AwayDayRepository {
  @override
  double loadBudget() => 0;
}

class _FakeBudget extends BudgetNotifier {
  _FakeBudget() : super(_FakeAwayRepo());
}

PlClub club(String key, String name, String tla) => PlClub(
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

final _arsenal = club('arsenal', 'Arsenal', 'ARS');
final _clubs = <PlClub>[
  _arsenal,
  club('man_city', 'Manchester City', 'MCI'),
];

FootballMatch match({
  int id = 1,
  required DateTime kickoff,
  String status = 'SCHEDULED',
  String homeName = 'Arsenal',
  String homeShort = 'Arsenal',
  String? homeTla = 'ARS',
  String awayName = 'Manchester City',
  String awayShort = 'Man City',
  String? awayTla = 'MCI',
}) =>
    FootballMatch(
      id: id,
      kickoffUtc: kickoff,
      status: status,
      matchday: 1,
      homeName: homeName,
      awayName: awayName,
      homeShort: homeShort,
      awayShort: awayShort,
      homeTla: homeTla,
      awayTla: awayTla,
    );

List<Override> _overrides({
  PlClub? favorite,
  List<FootballMatch> matches = const [],
  List<ClubCard> cards = const [],
}) =>
    [
      clubsProvider.overrideWith((ref) async => _clubs),
      favoriteClubProvider.overrideWithValue(favorite),
      matchesProvider.overrideWith(
        (ref) async => FootballResult(matches, DataSource.sample, null),
      ),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      tickProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      cardCollectionProvider.overrideWithValue(cards),
      stampsProvider.overrideWithValue(const <Block>[]),
      awayDayTotalsProvider.overrideWithValue((idr: 0.0, gbp: 0.0)),
      awayDayBudgetProvider.overrideWith((ref) => _FakeBudget()),
    ];

Widget _app(
  WidgetTester tester, {
  required List<Override> overrides,
  double textScale = 1.0,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: HomeTab()),
        ),
      ),
    );

void main() {
  testWidgets('(a) tanpa tim favorit menampilkan ajakan pilih tim',
      (tester) async {
    await tester.pumpWidget(_app(tester, overrides: _overrides()));
    await tester.pumpAndSettle();

    expect(find.text('Pilih tim favoritmu'), findsOneWidget);
    expect(find.text('Pilih tim'), findsOneWidget);
  });

  testWidgets('(b) tim favorit + laga menampilkan lawan, tombol, countdown',
      (tester) async {
    final kickoff = DateTime.now()
        .toUtc()
        .add(const Duration(days: 2, hours: 3, minutes: 15));
    await tester.pumpWidget(
      _app(
        tester,
        overrides: _overrides(
          favorite: _arsenal,
          matches: [match(id: 1, kickoff: kickoff)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Man City'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'Prediksi'), findsOneWidget);
    expect(find.textContaining(' hr '), findsWidgets);
  });

  testWidgets('(c) koleksi kartu kosong menampilkan ajakan main',
      (tester) async {
    await tester.pumpWidget(
      _app(tester, overrides: _overrides(favorite: _arsenal)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Belum ada kartu'), findsOneWidget);
  });

  testWidgets('(d) 320dp + textScaler 1.3 tanpa overflow (tanpa favorit)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(tester, overrides: _overrides(), textScale: 1.3),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('(d) 320dp + textScaler 1.3 tanpa overflow (dengan favorit)',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final kickoff = DateTime.now()
        .toUtc()
        .add(const Duration(days: 2, hours: 3, minutes: 15));
    await tester.pumpWidget(
      _app(
        tester,
        overrides: _overrides(
          favorite: _arsenal,
          matches: [match(id: 1, kickoff: kickoff)],
        ),
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
