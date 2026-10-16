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
    directory = await Directory.systemTemp.createTemp('pending_sync');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('pending_sync_test');
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

  test('koleksi baru tetap pending sampai ditandai tersinkron', () async {
    expect(await OfflineSyncDatabase.pendingCollections(), isEmpty);

    await OfflineSyncDatabase.persist('away_day_expenses', '[]');
    await OfflineSyncDatabase.persist('score_predictions', '[]');

    final pending = await OfflineSyncDatabase.pendingCollections();
    expect(pending..sort(), ['away_day_expenses', 'score_predictions']);

    await OfflineSyncDatabase.markSynced(
      await OfflineSyncDatabase.pendingRevisions(),
    );
    expect(await OfflineSyncDatabase.pendingCollections(), isEmpty);
  });

  test('menandai satu koleksi tidak membersihkan koleksi lain', () async {
    await OfflineSyncDatabase.persist('passport_chain', '[]');
    await OfflineSyncDatabase.persist('score_predictions', '[]');

    await OfflineSyncDatabase.markSynced({'score_predictions': 1});

    expect(await OfflineSyncDatabase.pendingCollections(), ['passport_chain']);
  });
}
