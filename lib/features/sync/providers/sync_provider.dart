import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../away_day/providers/away_day_providers.dart';
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

  Future<void> save(DateTime at) => HiveService.cache.put(_key, '${at.millisecondsSinceEpoch}');
}

final lastSyncStoreProvider = Provider((ref) => LastSyncStore());

final lastSyncedAtProvider = Provider<DateTime?>((ref) {
  // Sengaja tidak Riverpod state: dibaca ulang tiap kali profil dibangun.
  return ref.watch(lastSyncStoreProvider).load();
});

/// Status sinkronisasi yang ditampilkan di Profil.
class SyncState {
  const SyncState({this.busy = false, this.result, this.error});

  final bool busy;
  final SyncResult? result;
  final String? error;

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
            chain: _ref
                .watch(chainProvider)
                .map((b) => b.toJson())
                .toList(),
            predictions: _ref.read(predictionsProvider),
          );
      await _ref.read(lastSyncStoreProvider).save(DateTime.now());
      state = SyncState(result: result);
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

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
    (ref) => SyncNotifier(ref));
