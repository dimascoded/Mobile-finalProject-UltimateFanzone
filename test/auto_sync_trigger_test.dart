import 'dart:io';

// `fake_async` datang bersama `flutter_test` (transitive). Dioverifikasi di sini
// supaya analisis tetap bersih tanpa menambah dev_dependency di pubspec.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/network/connectivity_provider.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/sync/data/sync_repository.dart';
import 'package:ultimate_fanzone/features/sync/providers/sync_provider.dart';

/// SyncRepository palsu: cukup mencatat berapa kali `sync()` dipanggil.
class _FakeSyncRepository implements SyncRepository {
  int calls = 0;

  @override
  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    List<({String collection, String itemId})> deletions = const [],
    Map<String, dynamic>? feedback,
  }) async {
    calls++;
    return const SyncResult();
  }
}

/// Penyimpanan waktu sync tanpa I/O, supaya `markNow()` selesai di dalam zona
/// fakeAsync (tulis Hive nyata bisa meninggalkan Future yang menggantung).
class _NoopLastSyncStore implements LastSyncStore {
  @override
  DateTime? load() => null;

  @override
  Future<void> save(DateTime at) async {}
}

void main() {
  // `automaticSyncProvider` membuat AppLifecycleListener, jadi binding perlu
  // siap sebelum test berbasis container berjalan.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late _FakeSyncRepository fake;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('auto_sync_trigger');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('auto_sync_trigger_box');
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  setUp(() {
    fake = _FakeSyncRepository();
  });

  ProviderContainer buildContainer({required bool hasSession}) {
    return ProviderContainer(
      overrides: [
        // Seam: tidak menyentuh Supabase sama sekali.
        sessionAvailableProvider.overrideWithValue(hasSession),
        // Dianggap online sejak awal supaya penjadwalan langsung jalan.
        onlineProvider.overrideWith((_) => Stream<bool>.value(true)),
        syncRepositoryProvider.overrideWithValue(fake),
        lastSyncStoreProvider.overrideWithValue(_NoopLastSyncStore()),
      ],
    );
  }

  test('(a) tanpa sesi: repository tidak pernah dipanggil', () {
    fakeAsync((async) {
      final container = buildContainer(hasSession: false);
      // `listen` menjaga provider autoDispose tetap hidup seperti
      // `ref.watch(automaticSyncProvider)` di DashboardScreen.
      final sub = container.listen(automaticSyncProvider, (_, __) {});
      async.elapse(const Duration(seconds: 1));
      expect(fake.calls, 0);
      sub.close();
      container.dispose();
    });
  });

  test('(b) dengan sesi & online: mount memicu tepat satu sync dalam 1 detik',
      () {
    fakeAsync((async) {
      final container = buildContainer(hasSession: true);
      final sub = container.listen(automaticSyncProvider, (_, __) {});
      async.elapse(const Duration(seconds: 1));
      expect(fake.calls, 1);
      sub.close();
      container.dispose();
    });
  });

  test('(c) dispose membatalkan timer tertunda: tidak ada sync setelahnya', () {
    fakeAsync((async) {
      final container = buildContainer(hasSession: true);
      final sub = container.listen(automaticSyncProvider, (_, __) {});
      // Biarkan penjadwalan pertama (microtask) berjalan, lalu buang provider
      // sebelum debounce sempat menyala.
      async.flushMicrotasks();
      sub.close();
      container.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(fake.calls, 0);
    });
  });
}
