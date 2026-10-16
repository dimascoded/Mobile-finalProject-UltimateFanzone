import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'hive_service.dart';

class OfflineSyncDatabase {
  OfflineSyncDatabase._();

  static const collections = [
    'away_day_expenses',
    'passport_chain',
    'score_predictions',
  ];

  static Database? _database;

  static Future<void> initialize({
    DatabaseFactory? factory,
    String? path,
  }) async {
    if (_database != null) return;
    final DatabaseFactory selectedFactory;
    if (factory != null) {
      selectedFactory = factory;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      selectedFactory = ffi.databaseFactoryFfi;
    } else {
      selectedFactory = databaseFactory;
    }

    var dbPath = path;
    if (dbPath == null) {
      final root = await getApplicationSupportDirectory();
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}databases',
      );
      await directory.create(recursive: true);
      dbPath = '${directory.path}${Platform.pathSeparator}'
          'smart_football_fan.db';
    }
    _database = await selectedFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
          CREATE TABLE sync_documents (
            collection TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            revision INTEGER NOT NULL,
            synced_revision INTEGER NOT NULL DEFAULT 0
          )
        ''');
          await db.execute('''
          CREATE TABLE sync_deletions (
            collection TEXT NOT NULL,
            item_id TEXT NOT NULL,
            PRIMARY KEY (collection, item_id)
          )
        ''');
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE sync_deletions (
                collection TEXT NOT NULL,
                item_id TEXT NOT NULL,
                PRIMARY KEY (collection, item_id)
              )
            ''');
          }
        },
      ),
    );
  }

  static Future<void> importHiveData() async {
    final db = _database;
    if (db == null) return;

    for (final collection in collections) {
      final rows = await db.query(
        'sync_documents',
        columns: ['payload'],
        where: 'collection = ?',
        whereArgs: [collection],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await HiveService.cache
            .put(collection, rows.first['payload'] as String);
        continue;
      }
      final legacy = HiveService.cache.get(collection);
      if (legacy != null) await write(collection, legacy);
    }
  }

  static Future<void> persist(String collection, String payload) async {
    await write(collection, payload);
    await HiveService.cache.put(collection, payload);
  }

  static Future<void> write(String collection, String payload) async {
    final db = _database;
    if (db == null) return;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_documents',
        columns: ['revision'],
        where: 'collection = ?',
        whereArgs: [collection],
        limit: 1,
      );
      final revision = rows.isEmpty ? 1 : (rows.first['revision'] as int) + 1;
      await txn.insert(
        'sync_documents',
        {
          'collection': collection,
          'payload': payload,
          'revision': revision,
          'synced_revision': rows.isEmpty ? 0 : rows.first['synced_revision'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  static Future<Map<String, String>> readAll() async {
    final rows = await _database?.query('sync_documents') ?? const [];
    return {
      for (final row in rows)
        row['collection'] as String: row['payload'] as String,
    };
  }

  static Future<Map<String, int>> pendingRevisions() async {
    final rows = await _database?.query(
          'sync_documents',
          columns: ['collection', 'revision'],
          where: 'revision > synced_revision',
        ) ??
        const [];
    return {
      for (final row in rows)
        row['collection'] as String: row['revision'] as int,
    };
  }

  /// Nama koleksi yang punya perubahan lokal belum dikirim ke server.
  ///
  /// Dipakai dialog keluar: kalau daftar ini tidak kosong, keluar akan
  /// menghapus data yang belum tersinkron.
  static Future<List<String>> pendingCollections() async =>
      (await pendingRevisions()).keys.toList();

  static Future<List<({String collection, String itemId})>>
      pendingDeletions() async {
    final rows = await _database?.query('sync_deletions') ?? const [];
    return [
      for (final row in rows)
        (
          collection: row['collection'] as String,
          itemId: row['item_id'] as String,
        ),
    ];
  }

  static Future<void> queueDeletion(String collection, String itemId) async {
    await _database?.insert(
      'sync_deletions',
      {'collection': collection, 'item_id': itemId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> markSynced(Map<String, int> revisions) async {
    final db = _database;
    if (db == null || revisions.isEmpty) return;
    await db.transaction((txn) async {
      for (final entry in revisions.entries) {
        await txn.rawUpdate(
          'UPDATE sync_documents SET synced_revision = ? '
          'WHERE collection = ? AND revision <= ?',
          [entry.value, entry.key, entry.value],
        );
      }
    });
  }

  static Future<void> markDeletionsSynced(
    List<({String collection, String itemId})> deletions,
  ) async {
    final db = _database;
    if (db == null || deletions.isEmpty) return;
    await db.transaction((txn) async {
      for (final deletion in deletions) {
        await txn.delete(
          'sync_deletions',
          where: 'collection = ? AND item_id = ?',
          whereArgs: [deletion.collection, deletion.itemId],
        );
      }
    });
  }

  static Future<void> clear() async {
    final db = _database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('sync_documents');
      await txn.delete('sync_deletions');
    });
  }

  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
