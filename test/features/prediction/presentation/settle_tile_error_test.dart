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

class _ThrowingSettleAction implements SettleAction {
  @override
  Future<SettledPrediction?> settle(FootballMatch m, Prediction p) async => null;

  @override
  Future<({SettledPrediction? settled, String? reason, String? debug})>
      settleDetailed(
    FootballMatch m,
    Prediction p,
  ) async =>
          throw Exception('uji gagal menulis blok');
}

void main() {
  testWidgets('Cek hasil: tombol aktif lagi dan SnackBar memuat alasan',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final match = FootballMatch(
      id: 42,
      kickoffUtc: DateTime.utc(2026, 2, 1),
      status: 'FINISHED',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
      homeScore: 2,
      awayScore: 1,
    );
    final prediction = Prediction(
      matchId: 42,
      homeScore: 2,
      awayScore: 1,
      salt: 'salt-42',
      commit: Prediction.computeCommit(
        matchId: 42,
        home: 'Arsenal',
        away: 'Chelsea',
        salt: 'salt-42',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settleActionProvider.overrideWith((ref) => _ThrowingSettleAction()),
          predictionPointsProvider.overrideWithValue(0),
          predictionHistoryProvider.overrideWithValue(
              const <({FootballMatch? match, Prediction prediction, int? points})>[]),
          unsettledPredictionsProvider.overrideWithValue(
              <({FootballMatch match, Prediction prediction})>[
            (match: match, prediction: prediction),
          ]),
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

    await tester.tap(find.text('Cek hasil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Cek hasil'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull,
        reason: 'tombol harus aktif kembali setelah exception');
    expect(find.text('uji gagal menulis blok'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
