import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/database/offline_sync_database.dart';
import 'package:ultimate_fanzone/core/network/connectivity_provider.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/auth/data/identity_store.dart';
import 'package:ultimate_fanzone/features/auth/presentation/logout_flow.dart';
import 'package:ultimate_fanzone/features/dashboard/providers/dashboard_provider.dart';

class _MemoryIdentityStore implements IdentityStore {
  final values = <String, String>{};

  @override
  String? get(String key) => values[key];

  @override
  Future<void> put(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.store, {this.userId})
      : super(
          const FlutterSecureStorage(),
          LocalAuthentication(),
          identityStore: store,
        );

  final _MemoryIdentityStore store;
  final String? userId;

  @override
  String? get currentUserId => userId;
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => confirmAndLogout(context, ref),
            child: const Text('keluar'),
          ),
        ),
      );
}

List<Override> _overrides({
  required bool online,
  required Future<String?> Function() attempt,
  String? userId,
}) =>
    [
      onlineProvider.overrideWith((ref) async* {
        yield online;
      }),
      logoutProvider.overrideWithValue(() async {}),
      logoutSyncAttemptProvider.overrideWithValue(attempt),
      authRepositoryProvider.overrideWithValue(
        _FakeAuthRepository(_MemoryIdentityStore(), userId: userId),
      ),
    ];

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: _LogoutButton()),
    ),
  );
  await tester.pump();
}

Future<void> _openLogout(WidgetTester tester) async {
  await tester.tap(find.text('keluar'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory directory;

  setUpAll(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('logout_flow');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('logout_flow_test');
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
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  testWidgets('tanpa data pending menampilkan dialog Keluar? biasa',
      (tester) async {
    await _pump(tester, _overrides(online: true, attempt: () async => null));
    await _openLogout(tester);

    expect(find.text('Keluar?'), findsOneWidget);
    expect(find.text('Data belum dicadangkan'), findsNothing);
  });

  testWidgets('koleksi prediksi pending tampil sebagai "Prediksi skor"',
      (tester) async {
    await OfflineSyncDatabase.persist('score_predictions', '[]');
    await _pump(tester, _overrides(online: true, attempt: () async => null));
    await _openLogout(tester);

    expect(find.text('Data belum dicadangkan'), findsOneWidget);
    expect(find.textContaining('Prediksi skor'), findsOneWidget);
    expect(find.text('Keluar tetap'), findsOneWidget);
    expect(find.text('Coba sinkron lagi'), findsOneWidget);
  });

  testWidgets('prefs profil pending tampil sebagai nama, klub, anggaran',
      (tester) async {
    final store = _MemoryIdentityStore();
    store.values[AuthRepository.prefsPendingKey('u1')] = 'true';
    await _pump(
      tester,
      [
        onlineProvider.overrideWith((ref) async* {
          yield true;
        }),
        logoutProvider.overrideWithValue(() async {}),
        logoutSyncAttemptProvider.overrideWithValue(() async => null),
        authRepositoryProvider
            .overrideWithValue(_FakeAuthRepository(store, userId: 'u1')),
      ],
    );
    await _openLogout(tester);

    expect(find.textContaining('Nama, klub favorit, dan anggaran'),
        findsOneWidget);
  });

  testWidgets('penghapusan pending tampil sebagai "Penghapusan belum terkirim"',
      (tester) async {
    await OfflineSyncDatabase.queueDeletion('score_predictions', '7');
    await _pump(tester, _overrides(online: true, attempt: () async => null));
    await _openLogout(tester);

    expect(find.textContaining('Penghapusan belum terkirim'), findsOneWidget);
  });

  testWidgets('kegagalan sinkron menampilkan baris penyebab',
      (tester) async {
    await OfflineSyncDatabase.persist('score_predictions', '[]');
    await _pump(
      tester,
      _overrides(
        online: true,
        attempt: () async => 'Gagal menyegarkan data',
      ),
    );
    await _openLogout(tester);

    expect(
      find.textContaining('Penyebab: Gagal menyegarkan data'),
      findsOneWidget,
    );
  });

  testWidgets('offline + pending menampilkan catatan offline tanpa sinkron',
      (tester) async {
    await OfflineSyncDatabase.persist('score_predictions', '[]');
    var attemptCalls = 0;
    await _pump(
      tester,
      _overrides(
        online: false,
        attempt: () async {
          attemptCalls++;
          return null;
        },
      ),
    );
    await _openLogout(tester);

    expect(find.textContaining('Perangkat sedang offline'), findsOneWidget);
    expect(attemptCalls, 0);
  });

  testWidgets('"Coba sinkron lagi" mengulang sekali dan memperbarui daftar',
      (tester) async {
    await OfflineSyncDatabase.persist('score_predictions', '[]');
    await OfflineSyncDatabase.persist('away_day_expenses', '[]');
    var attemptCalls = 0;
    await _pump(
      tester,
      _overrides(
        online: true,
        attempt: () async {
          attemptCalls++;
          if (attemptCalls == 2) {
            await OfflineSyncDatabase.markSynced({'score_predictions': 1});
          }
          return null;
        },
      ),
    );
    await _openLogout(tester);

    expect(find.textContaining('Prediksi skor'), findsOneWidget);
    expect(find.textContaining('Pengeluaran Away Day'), findsOneWidget);
    expect(attemptCalls, 1);

    await tester.tap(find.text('Coba sinkron lagi'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(attemptCalls, 2);
    expect(find.textContaining('Prediksi skor'), findsNothing);
    expect(find.textContaining('Pengeluaran Away Day'), findsOneWidget);
    // Batas satu coba-ulang: tombolnya tidak muncul lagi.
    expect(find.text('Coba sinkron lagi'), findsNothing);
  });
}
