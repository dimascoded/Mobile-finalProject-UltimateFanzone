import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/database/offline_sync_database.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/sync/data/sync_repository.dart';
import 'package:ultimate_fanzone/features/sync/providers/sync_provider.dart';

/// SyncRepository palsu untuk menguji pembersihan antrean hapus: sukses
/// mengembalikan `appliedDeletions`, gagal melempar SyncException.
class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository({required this.applyDeletions});

  final bool applyDeletions;
  List<({String collection, String itemId})> received = const [];

  @override
  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    List<({String collection, String itemId})> deletions = const [],
    Map<String, dynamic>? feedback,
  }) async {
    received = List.of(deletions);
    if (!applyDeletions) {
      throw SyncException('Gagal menghapus prediksi di cloud: boom');
    }
    return SyncResult(appliedDeletions: List.of(deletions));
  }
}

void main() {
  late Directory directory;
  late ProviderContainer container;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('sync_deletion');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('sync_deletion_test');
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
    container.dispose();
    await OfflineSyncDatabase.close();
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('hapus yang sukses dibersihkan dari antrean', () async {
    await OfflineSyncDatabase.queueDeletion('score_predictions', '42');
    final fake = _FakeSyncRepository(applyDeletions: true);
    container = ProviderContainer(
      overrides: [syncRepositoryProvider.overrideWithValue(fake)],
    );

    await container.read(syncProvider.notifier).run();

    expect(fake.received,
        [(collection: 'score_predictions', itemId: '42')]);
    expect(await OfflineSyncDatabase.pendingDeletions(), isEmpty);
    expect(container.read(syncProvider).ok, isTrue);
  });

  test('hapus yang gagal tetap mengantre dan menandai error', () async {
    await OfflineSyncDatabase.queueDeletion('score_predictions', '42');
    final fake = _FakeSyncRepository(applyDeletions: false);
    container = ProviderContainer(
      overrides: [syncRepositoryProvider.overrideWithValue(fake)],
    );

    await container.read(syncProvider.notifier).run();

    expect(fake.received,
        [(collection: 'score_predictions', itemId: '42')]);
    expect(await OfflineSyncDatabase.pendingDeletions(),
        [(collection: 'score_predictions', itemId: '42')]);
    expect(container.read(syncProvider).error, contains('Gagal menghapus'));
  });
}
