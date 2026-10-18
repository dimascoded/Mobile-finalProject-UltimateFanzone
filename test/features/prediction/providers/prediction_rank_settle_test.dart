import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  test('settling across a rank mints its rank card only once', () async {
    const owner = '0xowner';
    const matchId = 9001;
    const salt = 'rank-test-salt';
    final kickoff = DateTime.utc(2026, 2, 1);
    final prediction = Prediction(
      matchId: matchId,
      homeScore: 2,
      awayScore: 1,
      salt: salt,
      commit: Prediction.computeCommit(
        matchId: matchId,
        home: 'Arsenal',
        away: 'Chelsea',
        salt: salt,
      ),
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final match = FootballMatch(
      id: matchId,
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

    final chain = <Block>[Blockchain.genesis()];
    chain.add(Blockchain.next(
        chain,
        Prediction.blockTypeResult,
        {
          'match': 1,
          'points': 3,
        },
        owner));
    chain.add(Blockchain.next(
      chain,
      Prediction.blockTypeCommit,
      Prediction.commitData(
        matchId: matchId,
        home: 'Arsenal',
        away: 'Chelsea',
        commit: prediction.commit,
        at: DateTime.utc(2026, 1, 1),
      ),
      owner,
    ));

    final container = ProviderContainer(
      overrides: [
        chainRepositoryProvider
            .overrideWithValue(_MemoryChainRepository(chain)),
        walletAddressProvider.overrideWith((ref) async => owner),
        clubsProvider
            .overrideWith((ref) async => [_club('arsenal'), _club('chelsea')]),
      ],
    );
    addTearDown(container.dispose);

    final action = container.read(settleActionProvider);
    final first = await action.settle(match, prediction);
    expect(first?.rankUp?.key, 'peramal');

    await action.settle(match, prediction);

    final rankCards = container.read(chainProvider).where((block) =>
        block.type == 'card' &&
        block.data['source'] == 'rank' &&
        block.data['ref'] == 'rank:peramal');
    expect(rankCards, hasLength(1));
  });
}
