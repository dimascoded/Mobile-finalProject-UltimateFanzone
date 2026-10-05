import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
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
      final result = await _ref.read(syncRepositoryProvider).sync(
            expenses: _ref.read(awayDayProvider),
            // S1: pakai `read`, bukan `watch`, supaya tidak/langganan ulang
            // setiap build dan tidak memicu rebuild terus-menerus.
            chain: _ref.read(chainProvider).map((b) => b.toJson()).toList(),
            predictions: _ref.read(predictionsProvider),
          );

      // S1: terapkan hasil merge ke Hive lewat notifier masing-masing.
      await _ref.read(awayDayProvider.notifier).replaceAll(result.expenses);
      await _ref
          .read(predictionsProvider.notifier)
          .replaceAll(result.predictions);

      // S2: adopsi rantai server hanya bila valid, genesis sama, dan lebih
      // panjang dari rantai lokal.
      var adopted = false;
      if (result.remoteChain.isNotEmpty) {
        final remote = SyncRepository.parseChain(result.remoteChain);
        final local = _ref.read(chainProvider);
        if (Blockchain.canAdoptRemote(local, remote)) {
          await _ref.read(chainProvider.notifier).replaceAll(remote);
          adopted = true;
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
