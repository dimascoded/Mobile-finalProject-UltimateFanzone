import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide shortHash;
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/card_collection_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/widgets/card_reveal_overlay.dart';
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

ClubCard card(
  String clubKey, {
  CardRarity rarity = CardRarity.common,
  String source = 'penalty',
  int blockIndex = 1,
  String hash = 'abcdef0123456789abcdef',
  DateTime? earnedAt,
}) =>
    ClubCard(
      clubKey: clubKey,
      rarity: rarity,
      source: source,
      blockIndex: blockIndex,
      blockHash: hash,
      earnedAt: earnedAt ?? DateTime(2026, 1, 15),
    );

final _clubs = <PlClub>[
  club('arsenal', 'Arsenal', 'ARS'),
  club('chelsea', 'Chelsea', 'CHE'),
  club('liverpool', 'Liverpool', 'LIV'),
  club('everton', 'Everton', 'EVE'),
  club('fulham', 'Fulham', 'FUL'),
];

Widget wrap(List<ClubCard> cards, {Widget? child}) => ProviderScope(
      overrides: [
        clubsProvider.overrideWith((ref) async => _clubs),
        clubCrestProvider.overrideWithValue(const <String, String>{}),
        chainValidProvider.overrideWithValue(true),
        cardCollectionProvider.overrideWithValue(cards),
      ],
      child: MaterialApp(home: child ?? const CardCollectionScreen()),
    );

void main() {
  testWidgets('empty state tampil saat belum ada kartu', (tester) async {
    await tester.pumpWidget(wrap(const <ClubCard>[]));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Main Adu Penalti, Refleks Kiper'),
      findsOneWidget,
    );
  });

  testWidgets('grid menampilkan crest klub yang dimiliki dan "?" lainnya',
      (tester) async {
    final cards = [
      card('arsenal', rarity: CardRarity.common, blockIndex: 1),
      card('arsenal', rarity: CardRarity.epic, blockIndex: 2),
      card('chelsea', rarity: CardRarity.rare, blockIndex: 3),
      card('liverpool', rarity: CardRarity.legendary, blockIndex: 4),
    ];
    await tester.pumpWidget(wrap(cards));
    await tester.pumpAndSettle();

    expect(find.text('3 dari 5 klub terkumpul'), findsOneWidget);
    expect(find.text('ARS'), findsOneWidget);
    expect(find.text('CHE'), findsOneWidget);
    expect(find.text('LIV'), findsOneWidget);
    expect(find.text('Epik x2'), findsOneWidget);
    expect(find.text('?'), findsNWidgets(2));
  });

  testWidgets('tap kartu milik sendiri membuka sheet bukti keaslian',
      (tester) async {
    const hash = 'abcdef0123456789abcdef';
    final cards = [card('arsenal', blockIndex: 7, hash: hash)];
    await tester.pumpWidget(wrap(cards));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Arsenal'));
    await tester.pumpAndSettle();

    expect(find.text('Bukti keaslian'), findsOneWidget);
    expect(find.text('Catatan #7'), findsOneWidget);
    expect(find.text(shortHash(hash)), findsOneWidget);
  });

  testWidgets('kartu baru memicu overlay reveal dan tombol Lihat Koleksi',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        clubsProvider.overrideWith((ref) async => _clubs),
        clubCrestProvider.overrideWithValue(const <String, String>{}),
        chainValidProvider.overrideWithValue(true),
        cardCollectionProvider.overrideWithValue(const <ClubCard>[]),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CardRevealListener(child: Scaffold(body: SizedBox())),
        ),
      ),
    );

    expect(find.text('Lihat Koleksi'), findsNothing);

    container.read(lastEarnedCardProvider.notifier).state =
        card('arsenal', rarity: CardRarity.legendary);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Kartu baru!'), findsOneWidget);
    expect(find.text('Lihat Koleksi'), findsOneWidget);
    expect(container.read(lastEarnedCardProvider), isNull);
  });
}
