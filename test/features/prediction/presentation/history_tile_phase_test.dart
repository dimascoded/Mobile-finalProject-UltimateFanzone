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

FootballMatch _match(int id, DateTime kickoff) => FootballMatch(
      id: id,
      kickoffUtc: kickoff,
      status: 'TIMED',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
    );

Prediction _prediction(int matchId) => Prediction(
      matchId: matchId,
      homeScore: 2,
      awayScore: 1,
      salt: 'salt-$matchId',
      commit: Prediction.computeCommit(
        matchId: matchId,
        home: 'Arsenal',
        away: 'Chelsea',
        salt: 'salt-$matchId',
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  List<({FootballMatch? match, Prediction prediction, int? points})> history,
) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        predictionPointsProvider.overrideWithValue(0),
        predictionHistoryProvider.overrideWithValue(history),
        unsettledPredictionsProvider
            .overrideWithValue(const <({FootballMatch match, Prediction prediction})>[]),
        matchesProvider.overrideWith((ref) async =>
            FootballResult<List<FootballMatch>>(
                const <FootballMatch>[], DataSource.live, DateTime.utc(2026))),
        favoriteClubProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PredictionScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
      'laga yang sudah kickoff tidak pernah menampilkan "Menunggu kickoff"',
      (tester) async {
    final now = DateTime.now().toUtc();
    final live = _match(1, now.subtract(const Duration(minutes: 10)));
    final awaiting = _match(2, now.subtract(const Duration(hours: 4)));

    await _pump(tester, [
      (match: live, prediction: _prediction(1), points: null),
      (match: awaiting, prediction: _prediction(2), points: null),
    ]);

    expect(find.text('Sedang berlangsung'), findsOneWidget);
    expect(find.text('Menunggu hasil resmi'), findsOneWidget);
    expect(find.textContaining('Menunggu kickoff'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('laga yang masih di depan memakai label kickoff', (tester) async {
    final now = DateTime.now().toUtc();
    final future = _match(3, now.add(const Duration(hours: 3)));

    await _pump(tester, [
      (match: future, prediction: _prediction(3), points: null),
    ]);

    expect(find.textContaining('Menunggu kickoff'), findsOneWidget);
    expect(find.text('Sedang berlangsung'), findsNothing);
  });
}
