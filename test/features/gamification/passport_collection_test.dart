import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/card_collection_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/passport_screen.dart';
import 'package:ultimate_fanzone/features/gamification/providers/card_collection_provider.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';

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

ClubCard card(String clubKey, {CardRarity rarity = CardRarity.common}) =>
    ClubCard(
      clubKey: clubKey,
      rarity: rarity,
      source: 'penalty',
      blockIndex: 1,
      blockHash: 'abcdef0123456789abcdef',
      earnedAt: DateTime(2026, 1, 15),
    );

final _arsenal = club('arsenal', 'Arsenal', 'ARS');
final _clubs = <PlClub>[
  _arsenal,
  club('chelsea', 'Chelsea', 'CHE'),
  club('liverpool', 'Liverpool', 'LIV'),
  club('everton', 'Everton', 'EVE'),
  club('fulham', 'Fulham', 'FUL'),
];

Widget _app(
  WidgetTester tester,
  Widget home, {
  required List<Override> overrides,
  ThemeData? theme,
  double textScale = 1.0,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    );

List<Override> _passportOverrides({PlClub? favorite}) => [
      clubsProvider.overrideWith((ref) async => _clubs),
      favoriteClubProvider.overrideWithValue(favorite),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      chainValidProvider.overrideWithValue(true),
      stampsProvider.overrideWithValue(const <Block>[]),
      ownedClubsProvider.overrideWithValue(const <String>{}),
      cardCollectionProvider.overrideWithValue(const <ClubCard>[]),
      // GPS tidak disentuh: jarak selalu "tidak diukur".
      stampDistanceProvider.overrideWith((ref) => Future<int?>.value(null)),
    ];

List<Override> _collectionOverrides(List<ClubCard> cards) => [
      clubsProvider.overrideWith((ref) async => _clubs),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      chainValidProvider.overrideWithValue(true),
      cardCollectionProvider.overrideWithValue(cards),
    ];

void main() {
  group('PassportScreen', () {
    testWidgets('tanpa tim favorit menampilkan ajakan pilih tim',
        (tester) async {
      await tester.pumpWidget(
        _app(
          tester,
          const PassportScreen(),
          overrides: _passportOverrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pilih tim favorit dulu'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pilih tim'), findsOneWidget);
    });

    testWidgets('dengan tim favorit menampilkan cap stamp dan mode demo',
        (tester) async {
      // Viewport tinggi supaya seluruh daftar ter-layout tanpa menggulir.
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          tester,
          const PassportScreen(),
          overrides: _passportOverrides(favorite: _arsenal),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Cap stamp'), findsOneWidget);
      expect(find.text('Mode demo'), findsOneWidget);
      expect(find.text('Stamp stadion Arsenal'), findsOneWidget);
      expect(find.textContaining('Belum ada stamp'), findsOneWidget);
      expect(find.textContaining('Koleksi Kartu (0)'), findsOneWidget);
    });

    testWidgets(
      '320dp + textScaler 1.3 tanpa overflow (dengan tim favorit)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            tester,
            const PassportScreen(),
            overrides: _passportOverrides(favorite: _arsenal),
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('CardCollectionScreen', () {
    testWidgets('tanpa kartu menampilkan ajakan main', (tester) async {
      await tester.pumpWidget(
        _app(
          tester,
          const CardCollectionScreen(),
          overrides: _collectionOverrides(const <ClubCard>[]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 dari 5 klub terkumpul'), findsOneWidget);
      expect(find.textContaining('Main Adu Penalti'), findsOneWidget);
    });

    testWidgets('satu kartu tampil sebagai milik sendiri, sisanya terkunci',
        (tester) async {
      await tester.pumpWidget(
        _app(
          tester,
          const CardCollectionScreen(),
          overrides: _collectionOverrides([card('arsenal')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 dari 5 klub terkumpul'), findsOneWidget);
      expect(find.text('Arsenal'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });

    testWidgets(
      '320dp + textScaler 1.3 tanpa overflow (satu kartu)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            tester,
            const CardCollectionScreen(),
            overrides: _collectionOverrides([card('arsenal')]),
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}
