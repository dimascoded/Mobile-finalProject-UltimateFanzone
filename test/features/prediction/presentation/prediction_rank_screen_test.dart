import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/prediction/presentation/prediction_screen.dart';
import 'package:ultimate_fanzone/features/prediction/providers/prediction_provider.dart';

class _MemoryPredictionStore extends PredictionStore {
  @override
  List<Prediction> load() => [];

  @override
  Future<void> save(List<Prediction> list) async {}
}

Future<void> _pumpScreen(WidgetTester tester, int points) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        predictionStoreProvider.overrideWithValue(_MemoryPredictionStore()),
        predictionsProvider.overrideWith(
          (ref) => PredictionsNotifier(_MemoryPredictionStore()),
        ),
        predictionPointsProvider.overrideWithValue(points),
        unsettledPredictionsProvider.overrideWithValue(
          const <({FootballMatch match, Prediction prediction})>[],
        ),
        predictionHistoryProvider.overrideWithValue(
          const <({
            FootballMatch? match,
            Prediction prediction,
            int? points
          })>[],
        ),
        matchesProvider.overrideWith((ref) async => FootballResult(
              const <FootballMatch>[],
              DataSource.sample,
              DateTime.utc(2030),
            )),
        favoriteClubProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: const PredictionScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (points, rank, progress) in [
    (0, 'Pemula', '5 poin lagi menuju Peramal'),
    (20, 'Analis', '10 poin lagi menuju Ahli'),
  ]) {
    testWidgets('shows $rank rank and progress at $points points',
        (tester) async {
      addTearDown(tester.view.reset);
      await _pumpScreen(tester, points);

      expect(find.text(rank), findsOneWidget);
      expect(find.text('$points poin'), findsOneWidget);
      expect(find.text(progress), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expands scoring explanation without 320dp text overflow',
      (tester) async {
    addTearDown(tester.view.reset);
    await _pumpScreen(tester, 0);

    await tester.tap(find.text('Cara dapat poin'));
    await tester.pump();
    await tester.ensureVisible(find.text('Tanpa taruhan atau uang'));
    await tester.pump();

    expect(find.text('Tebakan pas: 3 poin'), findsOneWidget);
    expect(find.text('Meleset 1 gol: 2 poin'), findsOneWidget);
    expect(find.text('Meleset 2 gol: 1 poin'), findsOneWidget);
    expect(find.text('Arah hasil benar (menang/seri/kalah): +1 poin'),
        findsOneWidget);
    expect(find.text('Maksimal 4 poin per laga'), findsOneWidget);
    expect(find.text('Tanpa taruhan atau uang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
