import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/database/offline_sync_database.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
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

Block _genesis() => Block(
      index: 0,
      timestamp: 0,
      type: 'genesis',
      data: const {},
      owner: 'system',
      prevHash: '0' * 64,
      nonce: 0,
      hash: '0' * 64,
    );

Block _commit(int matchId) => Block(
      index: 1,
      timestamp: 1000,
      type: Prediction.blockTypeCommit,
      data: {'match': matchId, 'commit': 'commit-$matchId'},
      owner: '0xowner',
      prevHash: '0' * 64,
      nonce: 0,
      hash: '1',
    );

Prediction _prediction(int matchId) => Prediction(
      matchId: matchId,
      homeScore: 2,
      awayScore: 1,
      salt: 'salt$matchId',
      commit: 'commit$matchId',
      createdAt: DateTime.utc(2026, 8, 15, 14),
    );

FootballMatch _match(int matchId, {required DateTime kickoff}) => FootballMatch(
      id: matchId,
      kickoffUtc: kickoff,
      status: 'TIMED',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
    );

void main() {
  late Directory directory;
  final now = DateTime.utc(2026, 10, 19);
  final past = DateTime.utc(2026, 2, 1);
  final future = DateTime.utc(2026, 12, 1);

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('prediction_remove');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('prediction_remove_test');
  });

  setUp(() async {
    await OfflineSyncDatabase.initialize(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await OfflineSyncDatabase.clear();
    await HiveService.cache.clear();
  });

  tearDown(() async {
    await OfflineSyncDatabase.close();
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  ProviderContainer containerWith(List<Block> chain) {
    final container = ProviderContainer(overrides: [
      chainRepositoryProvider
          .overrideWithValue(_MemoryChainRepository(chain)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('remove laga yang kickoff-nya sudah lewat: hilang dari state, Hive, '
      'dan antre satu deletion', () async {
    final container = containerWith([_genesis()]);
    final notifier = container.read(predictionsProvider.notifier);
    await notifier.put(_prediction(9001));
    expect(container.read(predictionsProvider).length, 1);

    final removed =
        await notifier.remove(9001, kickoffUtc: past, nowUtc: now);

    expect(removed, isTrue);
    expect(container.read(predictionsProvider), isEmpty);
    expect(PredictionStore().load(), isEmpty, reason: 'Hive ikut dibersihkan');
    expect(
      await OfflineSyncDatabase.pendingDeletions(),
      [(collection: 'score_predictions', itemId: '9001')],
    );
  });

  test('remove laga yang belum kickoff ditolak dan prediksi tetap ada',
      () async {
    final container = containerWith([_genesis()]);
    final notifier = container.read(predictionsProvider.notifier);
    await notifier.put(_prediction(9002));

    final removed =
        await notifier.remove(9002, kickoffUtc: future, nowUtc: now);

    expect(removed, isFalse);
    expect(container.read(predictionsProvider).length, 1);
    expect(PredictionStore().load().length, 1);
    expect(await OfflineSyncDatabase.pendingDeletions(), isEmpty);
  });

  test('setelah remove, commit untuk laga itu tetap ditolak karena rantai '
      'sudah punya blok commit', () async {
    final match = _match(9001, kickoff: future);
    final container = ProviderContainer(overrides: [
      chainRepositoryProvider.overrideWithValue(
        _MemoryChainRepository([_genesis(), _commit(9001)]),
      ),
      matchesProvider.overrideWith((ref) async =>
          FootballResult<List<FootballMatch>>([match], DataSource.live, now)),
    ]);
    addTearDown(container.dispose);
    await container.read(matchesProvider.future);

    await container.read(predictionsProvider.notifier).put(_prediction(9001));
    await container
        .read(predictionsProvider.notifier)
        .remove(9001, kickoffUtc: past, nowUtc: now);

    await expectLater(
      container
          .read(predictionActionProvider)
          .commit(match: match, homeScore: 1, awayScore: 0),
      throwsA(isA<Exception>().having((e) => e.toString(), 'pesan',
          contains('sudah pernah diprediksi'))),
    );
  });
}
