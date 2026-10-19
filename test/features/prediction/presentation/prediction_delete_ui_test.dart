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

class _MemoryPredictionStore extends PredictionStore {
  _MemoryPredictionStore([List<Prediction>? initial])
      : _list = List<Prediction>.of(initial ?? const []);
  List<Prediction> _list;
  @override
  List<Prediction> load() => List<Prediction>.of(_list);
  @override
  Future<void> save(List<Prediction> list) async {
    _list = List<Prediction>.of(list);
  }
}

void main() {
  testWidgets('SettleTile: tombol "Hapus prediksi" muncul saat salt hilang',
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
          predictionStoreProvider
              .overrideWithValue(_MemoryPredictionStore([prediction])),
          matchesProvider.overrideWith((ref) async =>
              FootballResult<List<FootballMatch>>(
                  [match], DataSource.live, DateTime.utc(2026))),
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

    expect(find.text('Hapus prediksi'), findsOneWidget);
    expect(find.text('Cek hasil'), findsNothing);

    // Biarkan SnackBar gagal "Cek hasil" selesai dulu agar SnackBar hapus
    // tidak mengantre di belakangnya.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));

    // Batal: prediksi tetap ada.
    await tester.tap(find.text('Hapus prediksi'));
    await tester.pump();
    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Salt tebakan hilang, prediksi ini tidak bisa dibuka'),
      findsOneWidget,
    );

    // Hapus: tile benar-benar hilang dari daftar.
    await tester.tap(find.text('Hapus prediksi'));
    await tester.pump();
    await tester.tap(find.text('Hapus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Salt tebakan hilang, prediksi ini tidak bisa dibuka'),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Prediksi dihapus'), findsOneWidget);
  });

  testWidgets('HistoryTile: ikon hapus muncul bila kickoff sudah lewat',
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
      createdAt: DateTime.utc(2026, 3, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chainRepositoryProvider
              .overrideWithValue(_MemoryChainRepository([])),
          predictionStoreProvider.overrideWithValue(_MemoryPredictionStore()),
          predictionPointsProvider.overrideWithValue(0),
          predictionHistoryProvider.overrideWithValue(
              <({FootballMatch? match, Prediction prediction, int? points})>[
            (match: match, prediction: prediction, points: 4),
          ]),
          unsettledPredictionsProvider.overrideWithValue(
              <({FootballMatch match, Prediction prediction})>[]),
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
    expect(find.byTooltip('Hapus prediksi'), findsOneWidget);
  });

  testWidgets('Hapus: konfirmasi, lalu prediksi hilang', (tester) async {
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
      createdAt: DateTime.utc(2026, 3, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chainRepositoryProvider
              .overrideWithValue(_MemoryChainRepository([])),
          predictionStoreProvider
              .overrideWithValue(_MemoryPredictionStore([prediction])),
          predictionPointsProvider.overrideWithValue(0),
          predictionHistoryProvider.overrideWithValue(
              <({FootballMatch? match, Prediction prediction, int? points})>[
            (match: match, prediction: prediction, points: 4),
          ]),
          unsettledPredictionsProvider.overrideWithValue(
              <({FootballMatch match, Prediction prediction})>[]),
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

    await tester.tap(find.byTooltip('Hapus prediksi'));
    await tester.pump();
    expect(find.text('Hapus prediksi ini? Poin dan kartu yang sudah kamu dapat '
        'tidak berubah, dan laga ini tidak bisa diprediksi ulang.'), findsOneWidget);
    await tester.tap(find.text('Hapus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Prediksi dihapus'), findsOneWidget);
  });
}
