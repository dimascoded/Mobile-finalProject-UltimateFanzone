import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/user_data_cleanup.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../gamification/data/blockchain.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../prediction/providers/prediction_provider.dart';
import '../data/chain_reconcile.dart';
import '../data/sync_repository.dart';

/// Waktu sinkronisasi terakhir (epoch milidetik), disimpan di Hive.
///
/// Key Hive `app_cache` yang dipakai adalah `last_sync_at`; nilainya juga
/// termasuk [AuthRepository.userDataKeys] sehingga ikut terhapus saat logout.
class LastSyncStore {
  static const _key = 'last_sync_at';

  /// Baca waktu sinkronisasi terakhir, atau null bila belum pernah sinkron.
  DateTime? load() {
    final raw = HiveService.cache.get(_key);
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Simpan waktu sinkronisasi terakhir ke Hive `app_cache`.
  Future<void> save(DateTime at) =>
      HiveService.cache.put(_key, '${at.millisecondsSinceEpoch}');
}

/// Penyedia tunggal [LastSyncStore].
final lastSyncStoreProvider = Provider((ref) => LastSyncStore());

/// S3: waktu sinkronisasi terakhir disimpan sebagai state Riverpod supaya
/// Profil ikut berubah begitu sinkronisasi selesai, tanpa perlu rebuild manual.
///
/// State-nya `DateTime?`; null berarti belum pernah sinkron. Nilai awal
/// dibaca dari Hive `app_cache` (kunci `last_sync_at`).
class LastSyncedAtNotifier extends StateNotifier<DateTime?> {
  LastSyncedAtNotifier(this._store) : super(_store.load());
  final LastSyncStore _store;

  /// Tandai waktu sinkronisasi sekarang dan simpan ke Hive.
  ///
  /// Efek samping: menulis kunci `last_sync_at` di Hive `app_cache`.
  Future<void> markNow() async {
    final at = DateTime.now();
    await _store.save(at);
    state = at;
  }
}

/// Waktu sinkronisasi terakhir yang diketahui aplikasi.
///
/// StateProvider biasa (bukan `autoDispose`) karena dibaca layar Profil dan
/// perlu bertahan antar-m navigasi; sumber penyimpanan ada di
/// [LastSyncedAtNotifier].
final lastSyncedAtProvider =
    StateNotifierProvider<LastSyncedAtNotifier, DateTime?>(
  (ref) => LastSyncedAtNotifier(ref.watch(lastSyncStoreProvider)),
);

/// Status sinkronisasi yang ditampilkan di Profil.
///
/// State-nya `SyncState` immutable yang merangkum: sedang berjalan
/// (`busy`), hasil sinkronisasi terakhir (`result`), pesan galat (`error`),
/// dan apakah server menolak token (`unauthorized`).
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

/// Notifier sinkronisasi manual + otomatis.
///
/// State-nya [SyncState]. Tanggung jawab notifier ini:
///
/// - mendorong data lokal (pengeluaran, rantai, prediksi) dan revisi
///   SQLite ke server lewat [SyncRepository.sync];
/// - mengadopsi hasil merge server untuk pengeluaran dan prediksi (hanya bila
///   isinya benar-benar berbeda, supaya tidak memicu rebuild berulang);
/// - merekonsiliasi rantai paspor dengan aturan "cloud wins" — BLOK LOKAL
///   HANYA ditimpa bila rantai remote valid ([Blockchain.isValid]) dan
///   rekonsiliasi memutuskan `adoptRemote`; blok lokal yang tidak ada di
///   cloud dihitung sebagai blok terbuang dan TIDAK pernah ditambang ulang;
/// - mencatat waktu sinkronisasi terakhir dan mengklaim user id sebagai
///   pemilik data lokal (kunci Hive `last_user_id`);
/// - ketika server membalas 401, MEMUTUSKAN SESI lewat
///   [AuthNotifier.logout] sehingga UI kembali ke layar login.
///
/// Notifier tidak `autoDispose` (sinkronisasi harus bisa dipicu dari mana
/// saja), jadi tidak wajib cek `mounted` setelah `await` (aturan §3.5 hanya
/// berlaku untuk notifier `autoDispose`).
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._ref) : super(const SyncState());

  final Ref _ref;

  /// Ada permintaan run() lain saat sedang sibuk; jalankan sekali lagi setelah
  /// selesai supaya perubahan yang datang di tengah sinkronisasi tidak hilang.
  bool _rerun = false;

  /// Batas re-run berurutan dari satu panggilan awal, supaya tidak looping.
  static const _maxReruns = 3;

  /// Jalankan sinkronisasi satu siklus.
  ///
  /// Bila sedang berjalan, panggilan ini tidak menggandakan proses; ia
  /// menandai permintaan re-run sehingga siklus berikutnya dijalankan lagi
  /// (maksimal 3 kali berurutan dari satu pemanggilan awal). Efek samping:
  /// seluruh operasi sinkronisasi pada [SyncNotifier._runOnce].
  Future<void> run() async {
    if (state.busy) {
      _rerun = true;
      return;
    }
    var reruns = 0;
    while (true) {
      await _runOnce();
      if (_rerun && reruns < _maxReruns) {
        _rerun = false;
        reruns++;
        continue;
      }
      _rerun = false;
      break;
    }
  }

  /// Satu siklus sinkronisasi penuh.
  ///
  /// Mengirim revisi SQLite yang belum tersinkron (collections
  /// `away_day_expenses`, `passport_chain`, `score_predictions`) beserta
  /// antrean penghapusan, lalu mengadopsi hasil merge server. Rantai lokal
  /// hanya ditimpa bila rantai remote valid ([Blockchain.isValid]) dan
  /// rekonsiliasi memutuskan `adoptRemote`; blok lokal yang dibuang tidak
  /// pernah ditambang ulang. Galat 401 memicu logout, galat lain hanya
  /// mengisi [SyncState.error].
  ///
  /// Efek samping: menulis Hive `app_cache` (`away_day_expenses`,
  /// `score_predictions`, `passport_chain`, `last_sync_at`,
  /// `last_user_id`), memperbarui baris SQLite `sync_documents` dan
  /// `sync_deletions`, serta dapat memanggil [AuthNotifier.logout].
  Future<void> _runOnce() async {
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
      if (AppConfig.supabaseConfigured) {
        await OfflineSyncDatabase.markSynced(pendingRevisions);
      }
      // Hanya deletion yang benar-benar diterapkan ke cloud yang dibersihkan;
      // yang gagal tetap mengantre untuk siklus berikutnya (tanpa loop).
      await OfflineSyncDatabase.markDeletionsSynced(result.appliedDeletions);

      // S2: adopsi rantai cloud "cloud wins" saat rekonsiliasi memutuskan
      // demikian. Blok lokal yang tidak ada di cloud dibuang, TIDAK
      // ditambang ulang (khususnya blok 'card').
      var adopted = false;
      var dropped = 0;
      if (result.chainOutcome == ChainOutcome.adoptRemote) {
        final remote = SyncRepository.parseChain(result.remoteChain);
        if (Blockchain.isValid(remote)) {
          final local = _ref.read(chainProvider);
          if (jsonEncode(local.map((b) => b.toJson()).toList()) !=
              jsonEncode(remote.map((b) => b.toJson()).toList())) {
            await _ref.read(chainProvider.notifier).replaceAll(remote);
          }
          adopted = true;
          dropped = droppedLocalBlocks(local, remote);
        }
      } else if (result.remoteChain.isNotEmpty) {
        // Jalur HTTP lama (non-Supabase) masih ada; pertahankan perilaku
        // adopsinya.
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
      // H2: sinkron sukses berarti user id terkonfirmasi masih aktif → klaim
      // sebagai pemilik data lokal, supaya pergantian akun terdeteksi oleh
      // login berikutnya walau sesi lama masih hidup di perangkat.
      final authRepo = _ref.read(authRepositoryProvider);
      final syncedUserId = authRepo.currentUserId;
      if (syncedUserId != null) {
        await writeDataOwnerId(authRepo.identityStore, syncedUserId);
      }
      state = SyncState(
          result: SyncResult(
        pushedExpenses: result.pushedExpenses,
        pushedChain: result.pushedChain,
        pushedPredictions: result.pushedPredictions,
        mergedExpenses: result.mergedExpenses,
        mergedPredictions: result.mergedPredictions,
        expenses: result.expenses,
        predictions: result.predictions,
        remoteChain: result.remoteChain,
        chainOutcome: result.chainOutcome,
        droppedLocalBlocks: dropped,
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

/// Status sinkronisasi terakhir yang ditampilkan di Profil.
///
/// StateProvider biasa (bukan `autoDispose`) karena dibaca layar Profil dan
/// harus tetap menampilkan hasil/error sinkronisasi terakhir; sumber
/// perilakunya ada di [SyncNotifier].
final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) => SyncNotifier(ref));

/// Seam status sesi: true bila Supabase terkonfigurasi DAN ada sesi aktif.
///
/// Produksi membaca `AppConfig.supabaseConfigured` lalu `Supabase.instance`.
/// Semua dibungkus try/catch supaya lingkungan tanpa Supabase (mis. unit test)
/// dianggap "tanpa sesi" alih-alih melempar. Test meng-override provider ini
/// sehingga tidak perlu menyentuh Supabase.
///
/// Tanpa efek samping; hanya membaca state sesi.
final sessionAvailableProvider = Provider<bool>((ref) {
  if (!AppConfig.supabaseConfigured) return false;
  try {
    return supa.Supabase.instance.client.auth.currentSession != null;
  } catch (_) {
    return false;
  }
});

/// Apakah pesan galat berarti "tidak ada sesi" (jalur Supabase maupun HTTP).
///
/// Retry 30 detik percuma tanpa sesi, jadi timer retry dilewati untuk pesan ini.
///
/// Fungsi murni, tanpa efek samping.
bool _isNoSessionError(String message) =>
    message.contains('Masuk ke akun dulu') || message.contains('Belum login');

/// Menjaga sinkronisasi otomatis tetap hidup selama Dashboard ter-mount.
///
/// `autoDispose` penting: saat logout `DashboardScreen` dilepas, provider ikut
/// dibuang (timer debounce/retry, listener, timer periodik, lifecycle) sehingga
/// tidak ada percobaan sync maupun loop retry selagi aplikasi di layar login.
/// Saat login berikutnya Dashboard ter-mount lagi dan body ini dijalankan ulang.
///
/// Efek samping: menjadwalkan sinkronisasi (debounce 300 ms untuk sinkron
/// pertama, 900 ms untuk perubahan berikutnya), memasang timer periodik 5
/// menit, memasang [AppLifecycleListener] untuk sinkron saat aplikasi kembali
/// ke depan, dan mencoba sinkron ulang 30 detik setelah gagal — kecuali
/// galatnya berarti "tidak ada sesi", yang membuat retry dihentikan agar
/// tidak terjadi loop.
final automaticSyncProvider = Provider.autoDispose<void>((ref) {
  // Tanpa Supabase/sesi tidak ada yang bisa disinkronkan. Ini juga mematikan
  // auto-sync pada build non-Supabase, sama seperti perilaku sebelumnya.
  if (!ref.read(sessionAvailableProvider)) return;

  var disposed = false;
  Timer? debounce;
  Timer? retry;

  /// Sinkronisasi pertama setelah mount dipicu lebih cepat (300 ms) supaya data
  /// langsung terisi begitu login; perubahan berikutnya memakai 900 ms.
  var firstSchedule = true;

  void scheduleSync() {
    if (disposed) return;
    // Tanpa sesi (mis. setelah logout) jangan jadwalkan apa pun: batalkan
    // debounce/retry yang tertunda supaya tidak ada sync gagal maupun loop
    // retry 30 detik selama aplikasi berada di layar login.
    if (!ref.read(sessionAvailableProvider)) {
      debounce?.cancel();
      retry?.cancel();
      return;
    }
    if (ref.read(onlineProvider).valueOrNull != true) return;
    debounce?.cancel();
    retry?.cancel();
    final delay = firstSchedule
        ? const Duration(milliseconds: 300)
        : const Duration(milliseconds: 900);
    firstSchedule = false;
    debounce = Timer(delay, () {
      unawaited(ref.read(syncProvider.notifier).run());
    });
  }

  // Sinkron juga saat aplikasi kembali ke depan dan tiap 5 menit, supaya data
  // baru terkirim walau tidak ada perubahan provider yang terpicu.
  final lifecycle = AppLifecycleListener(onResume: scheduleSync);
  final periodic =
      Timer.periodic(const Duration(minutes: 5), (_) => scheduleSync());

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
      // Tanpa sesi ("Masuk ke akun dulu..."/"Belum login...") retry percuma;
      // berhenti sampai login berikutnya, jangan bikin loop 30 detik.
      if (!_isNoSessionError(next.error!)) {
        retry = Timer(const Duration(seconds: 30), scheduleSync);
      }
    } else if (next.ok) {
      retry?.cancel();
    }
  });
  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    retry?.cancel();
    lifecycle.dispose();
    periodic.cancel();
  });

  // Tarik data segera setelah Dashboard ter-mount (login), tanpa menunggu
  // perubahan provider atau pemicu berkala.
  Future.microtask(scheduleSync);
});
