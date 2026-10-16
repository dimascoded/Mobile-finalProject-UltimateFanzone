import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/database/offline_sync_database.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('offline_sync_db');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('offline_sync_test');
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

  test('imports legacy Hive data into SQLite and queues it for sync', () async {
    await HiveService.cache.put('away_day_expenses', '[{"title":"Tiket"}]');

    await OfflineSyncDatabase.importHiveData();

    expect(
      (await OfflineSyncDatabase.readAll())['away_day_expenses'],
      '[{"title":"Tiket"}]',
    );
    expect(
      await OfflineSyncDatabase.pendingRevisions(),
      {'away_day_expenses': 1},
    );
  });

  test('keeps new writes pending until acknowledged by a successful sync',
      () async {
    await OfflineSyncDatabase.persist('score_predictions', '[]');
    final firstRevision = await OfflineSyncDatabase.pendingRevisions();
    expect(firstRevision, {'score_predictions': 1});

    await OfflineSyncDatabase.markSynced(firstRevision);
    expect(await OfflineSyncDatabase.pendingRevisions(), isEmpty);

    await OfflineSyncDatabase.persist('score_predictions', '[{"matchId":1}]');
    expect(
      await OfflineSyncDatabase.pendingRevisions(),
      {'score_predictions': 2},
    );
  });

  test('clears local sync documents on account logout', () async {
    await OfflineSyncDatabase.persist('passport_chain', '[]');
    await OfflineSyncDatabase.queueDeletion('away_day_expenses', 'expense-1');

    await OfflineSyncDatabase.clear();

    expect(await OfflineSyncDatabase.readAll(), isEmpty);
    expect(await OfflineSyncDatabase.pendingRevisions(), isEmpty);
    expect(await OfflineSyncDatabase.pendingDeletions(), isEmpty);
  });

  test('keeps deletion tombstones pending until cloud acknowledgement',
      () async {
    await OfflineSyncDatabase.queueDeletion('away_day_expenses', 'expense-1');

    final pending = await OfflineSyncDatabase.pendingDeletions();
    expect(
      pending,
      [(collection: 'away_day_expenses', itemId: 'expense-1')],
    );

    await OfflineSyncDatabase.markDeletionsSynced(pending);

    expect(await OfflineSyncDatabase.pendingDeletions(), isEmpty);
  });
}
