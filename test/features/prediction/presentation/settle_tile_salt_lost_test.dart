import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/prediction/presentation/prediction_screen.dart';
import 'package:ultimate_fanzone/features/prediction/providers/prediction_provider.dart';

class _MemoryChainRepository extends ChainRepository {
  _MemoryChainRepository(this._chain);
  List<Block> _chain;
  @override
  List<Block> load() => List<Block>.of(_chain);
  @override
  Future<void> save(List<Block> chain) async {
    _chain = List<Block>.of(chain);
  }
}

void main() {
  testWidgets('reveal hash mismatch: pesan salt hilang, tanpa tombol, + debug',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final kickoff = DateTime.utc(2026, 2, 1);
    final match = FootballMatch(
      id: 42,
      kickoffUtc: kickoff,
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
      salt: 'salt-lokal',
      commit: 'commit-tebakan-lokal',
    );
    final chain = <Block>[
      Block(
        index: 0,
        timestamp: 0,
        type: 'genesis',
        data: const {},
        owner: 'system',
        prevHash: '0' * 64,
        nonce: 0,
        hash: '0' * 64,
      ),
      Block(
        index: 1,
        timestamp: kickoff.subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/ 1000,
        type: Prediction.blockTypeCommit,
        data: {
          'match': 42,
          'home': 'Arsenal',
          'away': 'Chelsea',
          'commit': 'blok-commit-lama',
          'at': kickoff.subtract(const Duration(hours: 1)).toIso8601String(),
        },
        owner: '0xowner',
        prevHash: '0' * 64,
        nonce: 0,
        hash: '1',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chainRepositoryProvider
              .overrideWithValue(_MemoryChainRepository(chain)),
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

    expect(
      find.text('Salt tebakan hilang, prediksi ini tidak bisa dibuka'),
      findsOneWidget,
    );
    expect(find.textContaining('commit_sama=false'), findsOneWidget);
    expect(find.text('Cek hasil'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
