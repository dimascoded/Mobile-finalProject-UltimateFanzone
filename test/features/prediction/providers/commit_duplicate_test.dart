import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
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
  List<Prediction> _list = [];
  @override
  List<Prediction> load() => List<Prediction>.of(_list);
  @override
  Future<void> save(List<Prediction> list) async {
    _list = List<Prediction>.of(list);
  }
}

PlClub _club(String key) => PlClub(
      key: key,
      name: '$key FC',
      shortName: key,
      tla: key.substring(0, 3).toUpperCase(),
      city: 'Kota',
      stadium: 'Stadion',
      lat: 0,
      lng: 0,
      color: 0xFF000000,
      aliases: [key],
    );

void main() {
  const owner = '0xowner';
  final now = DateTime.now().toUtc();
  final kickoff = now.add(const Duration(hours: 2));

  FootballMatch upcoming() => FootballMatch(
        id: 9001,
        kickoffUtc: kickoff,
        status: 'TIMED',
        matchday: 1,
        homeName: 'Arsenal',
        awayName: 'Chelsea',
        homeShort: 'ARS',
        awayShort: 'CHE',
      );
  FootballMatch finished() => FootballMatch(
        id: 9001,
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

  Block oldCommit() => Block(
        index: 1,
        timestamp: now.millisecondsSinceEpoch ~/ 1000,
        type: Prediction.blockTypeCommit,
        data: {
          'match': 9001,
          'home': 'Arsenal',
          'away': 'Chelsea',
          'commit': 'blok-lama-tanpa-salt-lokal',
          'at': now.subtract(const Duration(hours: 1)).toIso8601String(),
        },
        owner: owner,
        prevHash: '0' * 64,
        nonce: 0,
        hash: '1',
      );

  List<Override> overrides(List<Block> chain) => [
        chainRepositoryProvider
            .overrideWithValue(_MemoryChainRepository(chain)),
        predictionStoreProvider.overrideWithValue(_MemoryPredictionStore()),
        walletAddressProvider.overrideWith((ref) async => owner),
        matchesProvider.overrideWith((ref) async =>
            FootballResult<List<FootballMatch>>(
                [upcoming()], DataSource.live, now)),
        clubsProvider
            .overrideWith((ref) async => [_club('arsenal'), _club('chelsea')]),
      ];

  test('commit kedua ditolak bila rantai sudah punya commit tanpa prediksi',
      () async {
    final container = ProviderContainer(
      overrides: overrides([Blockchain.genesis(), oldCommit()]),
    );
    addTearDown(container.dispose);
    await container.read(matchesProvider.future);

    await expectLater(
      container
          .read(predictionActionProvider)
          .commit(match: upcoming(), homeScore: 2, awayScore: 1),
      throwsA(isA<Exception>().having((e) => e.toString(), 'pesan',
          contains('sudah pernah diprediksi'))),
    );

    final commits = container
        .read(chainProvider)
        .where((b) =>
            b.type == Prediction.blockTypeCommit && b.data['match'] == 9001)
        .length;
    expect(commits, 1, reason: 'tidak boleh ada blok commit kedua');
  });

  test('happy path: commit -> reveal valid -> poin', () async {
    final container = ProviderContainer(
      overrides: overrides([Blockchain.genesis()]),
    );
    addTearDown(container.dispose);
    await container.read(matchesProvider.future);

    final result = await container
        .read(predictionActionProvider)
        .commit(match: upcoming(), homeScore: 2, awayScore: 1);
    expect(result.alreadyCommitted, isFalse);

    final settled = await container
        .read(settleActionProvider)
        .settle(finished(), result.prediction);
    expect(settled, isNotNull);
    expect(settled!.valid, isTrue);
    expect(settled.points, 4);
  });
}
