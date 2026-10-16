import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/sync/data/sync_repository.dart';
import 'package:ultimate_fanzone/features/sync/providers/sync_provider.dart';

/// SyncRepository palsu: `sync()` selesai setelah jeda yang bisa diatur, dan
/// mencatat berapa kali dipanggil serta apakah ada panggilan yang tumpang
/// tindih (maxActive > 1 berarti tidak terserialisasi).
class _FakeSyncRepository implements SyncRepository {
  Duration delay = const Duration(milliseconds: 20);

  /// Dipanggil di awal setiap sync(), dipakai untuk memicu run() lagi saat
  /// sibuk (meniru perubahan data di tengah sinkronisasi).
  void Function()? onCall;

  int calls = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<SyncResult> sync({
    required List<AwayDayExpense> expenses,
    required List<Map<String, dynamic>> chain,
    required List<Prediction> predictions,
    List<({String collection, String itemId})> deletions = const [],
    Map<String, dynamic>? feedback,
  }) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    onCall?.call();
    await Future<void>.delayed(delay);
    active--;
    return const SyncResult();
  }
}

void main() {
  late Directory directory;
  late ProviderContainer container;
  late _FakeSyncRepository fake;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('sync_rerun');
    Hive.init(directory.path);
    HiveService.cache = await Hive.openBox<String>('sync_rerun_test_box');
  });

  setUp(() {
    fake = _FakeSyncRepository();
    container = ProviderContainer(
      overrides: [syncRepositoryProvider.overrideWithValue(fake)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('run kedua menunggu, lalu dijalankan sekali lagi setelah yang pertama selesai',
      () async {
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.run();
    final second = notifier.run(); // sibuk -> tandai untuk re-run

    await Future.wait([first, second]);

    expect(fake.calls, 2);
    // Tidak pernah dua sync() berjalan bersamaan.
    expect(fake.maxActive, 1);
  });

  test('tiga panggilan cepat tidak melebihi 1 + 3 invocations', () async {
    final notifier = container.read(syncProvider.notifier);

    final first = notifier.run();
    final extras = [notifier.run(), notifier.run(), notifier.run()];

    await Future.wait([first, ...extras]);

    expect(fake.calls, greaterThanOrEqualTo(1));
    expect(fake.calls, lessThanOrEqualTo(4));
    expect(fake.maxActive, 1);
  });

  test('re-run berurutan dibatasi 3 (satu panggilan + 3 re-run)', () async {
    fake.delay = const Duration(milliseconds: 5);
    final notifier = container.read(syncProvider.notifier);
    // Setiap sync memicu run() lagi selagi sibuk -> rantai re-run tanpa henti
    // kalau tidak dibatasi.
    fake.onCall = notifier.run;

    await notifier.run();

    expect(fake.calls, 4);
    expect(fake.maxActive, 1);
  });
}
