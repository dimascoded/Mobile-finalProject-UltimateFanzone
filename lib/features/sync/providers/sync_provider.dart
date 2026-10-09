import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../gamification/data/blockchain.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../prediction/providers/prediction_provider.dart';
import '../data/sync_repository.dart';

/// Waktu sinkronisasi terakhir (epoch milidetik), disimpan di Hive.
class LastSyncStore {
  static const _key = 'last_sync_at';

  DateTime? load() {
    final raw = HiveService.cache.get(_key);
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> save(DateTime at) =>
      HiveService.cache.put(_key, '${at.millisecondsSinceEpoch}');
}

final lastSyncStoreProvider = Provider((ref) => LastSyncStore());

/// S3: waktu sinkronisasi terakhir disimpan sebagai state Riverpod supaya
/// Profil ikut berubah begitu sinkronisasi selesai, tanpa perlu rebuild manual.
class LastSyncedAtNotifier extends StateNotifier<DateTime?> {
  LastSyncedAtNotifier(this._store) : super(_store.load());
  final LastSyncStore _store;

  Future<void> markNow() async {
    final at = DateTime.now();
    await _store.save(at);
    state = at;
  }
}

final lastSyncedAtProvider =
    StateNotifierProvider<LastSyncedAtNotifier, DateTime?>(
  (ref) => LastSyncedAtNotifier(ref.watch(lastSyncStoreProvider)),
);

/// Status sinkronisasi yang ditampilkan di Profil.
class SyncState {
  const SyncState({
    this.busy = false,
    this.result,
    this.error,
    this.unauthorized = false,
  });

  final bool busy;
  final SyncResult? result;
  final String? error;

  /// true = server menolak token; sesi sudah dihapus (S3).
  final bool unauthorized;

  bool get ok => error == null && result != null;
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._ref) : super(const SyncState());

  final Ref _ref;

  Future<void> run() async {
    if (state.busy) return;
    state = const SyncState(busy: true);
    try {
      final pendingRevisions = await OfflineSyncDatabase.pendingRevisions();
      final pendingDeletions = await OfflineSyncDatabase.pendingDeletions();
      final result = await _ref.read(syncRepositoryProvider).sync(
            expenses: _ref.read(awayDayProvider),
            deletions: pendingDeletions,
            // S1: pakai `read`, bukan `watch`, supaya tidak/langganan ulang
            // setiap build dan tidak memicu rebuild terus-menerus.
            chain: _ref.read(chainProvider).map((b) => b.toJson()).toList(),
            predictions: _ref.read(predictionsProvider),
          );

      // Avoid notifying auto-sync listeners when the merged data is unchanged.
      final localExpenses = _ref.read(awayDayProvider);
      if (jsonEncode(localExpenses.map((e) => e.toJson()).toList()) !=
          jsonEncode(result.expenses.map((e) => e.toJson()).toList())) {
        await _ref.read(awayDayProvider.notifier).replaceAll(result.expenses);
      }
      final localPredictions = _ref.read(predictionsProvider);
      if (jsonEncode(localPredictions.map((p) => p.toJson()).toList()) !=
          jsonEncode(result.predictions.map((p) => p.toJson()).toList())) {
        await _ref
            .read(predictionsProvider.notifier)
            .replaceAll(result.predictions);
      }
      if (!result.mock) {
        await OfflineSyncDatabase.markSynced(pendingRevisions);
        if (AppConfig.supabaseConfigured) {
          await OfflineSyncDatabase.markDeletionsSynced(pendingDeletions);
        }
      }

      // S2: adopsi rantai server hanya bila valid, genesis sama, dan lebih
      // panjang dari rantai lokal.
      var adopted = false;
      if (result.remoteChain.isNotEmpty) {
        final remote = SyncRepository.parseChain(result.remoteChain);
        final local = _ref.read(chainProvider);
        if (Blockchain.canAdoptRemote(local, remote)) {
          if (jsonEncode(local.map((b) => b.toJson()).toList()) !=
              jsonEncode(remote.map((b) => b.toJson()).toList())) {
            await _ref.read(chainProvider.notifier).replaceAll(remote);
            adopted = true;
          }
        }
      }

      await _ref.read(lastSyncedAtProvider.notifier).markNow();
      state = SyncState(
          result: SyncResult(
        pushedExpenses: result.pushedExpenses,
        pushedChain: result.pushedChain,
        pushedPredictions: result.pushedPredictions,
        mergedExpenses: result.mergedExpenses,
        mergedPredictions: result.mergedPredictions,
        mock: result.mock,
        expenses: result.expenses,
        predictions: result.predictions,
        remoteChain: result.remoteChain,
        adoptedChain: adopted,
      ));
    } on SyncException catch (e) {
      if (e.unauthorized) {
        // S3: token tidak berlaku/berakhir -> hapus sesi agar UI kembali ke
        // layar login.
        await _ref.read(authProvider.notifier).logout();
      }
      state = SyncState(error: e.message, unauthorized: e.unauthorized);
    } catch (e) {
      state = SyncState(error: _message(e));
    }
  }

  /// Ambil pesan yang lebih berguna: server memang mengirim teks error.
  String _message(Object e) {
    final s = e.toString();
    if (s.contains('Exception: ')) return s.split('Exception: ').last;
    return s;
  }
}

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) => SyncNotifier(ref));

final automaticSyncProvider = Provider<void>((ref) {
  if (!AppConfig.supabaseConfigured && AppConfig.backendUrl.isEmpty) return;

  Timer? debounce;
  Timer? retry;
  void scheduleSync() {
    if (ref.read(onlineProvider).valueOrNull != true) return;
    debounce?.cancel();
    retry?.cancel();
    debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(ref.read(syncProvider.notifier).run());
    });
  }

  ref.listen<AsyncValue<bool>>(onlineProvider, (previous, next) {
    if (next.valueOrNull == true && previous?.valueOrNull != true) {
      scheduleSync();
    }
  });
  ref.listen(awayDayProvider, (_, __) => scheduleSync());
  ref.listen(chainProvider, (_, __) => scheduleSync());
  ref.listen(predictionsProvider, (_, __) => scheduleSync());
  ref.listen<SyncState>(syncProvider, (_, next) {
    if (next.error != null) {
      retry?.cancel();
      retry = Timer(const Duration(seconds: 30), scheduleSync);
    } else if (next.ok) {
      retry?.cancel();
    }
  });
  ref.onDispose(() {
    debounce?.cancel();
    retry?.cancel();
  });
});
