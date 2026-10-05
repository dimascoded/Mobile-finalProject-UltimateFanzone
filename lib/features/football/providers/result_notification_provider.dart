import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/utils/time_utils.dart';
import '../../sos_emergency/data/notification_service.dart';
import '../data/football_repository.dart';
import '../data/models.dart';
import 'football_providers.dart';

/// Batas usia hasil laga agar notifikasi tidak membanjiri pengguna.
/// Laga yang selesai lebih lama dari ini tidak dinotifikasi.
const resultNotifyMaxAge = Duration(hours: 6);

/// Id laga yang hasil akhirnya sudah pernah dinotifikasi.
final notifiedMatchIdsProvider = StateProvider<Set<int>>((ref) => const {});

/// Signature penjadwalan hasil agar tidak dijadwalkan ulang setiap data berubah:
/// `matchId@kickoffUtc`.
final _scheduledResultsProvider =
    StateProvider<Map<String, DateTime>>((ref) => const {});

String _sig(FootballMatch m) =>
    '${m.id}@${m.kickoffUtc.toUtc().toIso8601String()}';

class NotifiedStore {
  static const _key = 'notified_results';

  /// Baca daftar id laga sebagai `Set<int>` dari JSON.
  Set<int> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null || raw.isEmpty) return <int>{};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // Format lama (`'#1;#2;'`) atau rusak: mulai dari daftar kosong.
      return <int>{};
    }
    if (decoded is! List) return <int>{};
    return decoded.whereType<num>().map((e) => e.toInt()).toSet();
  }

  /// Simpan sebagai JSON `List<int>` (bukan lagi string `'#id;'`).
  Future<void> save(Set<int> ids) =>
      HiveService.cache.put(_key, jsonEncode(ids.toList()..sort()));
}

final notifiedStoreProvider = Provider((ref) => NotifiedStore());

/// Bangun judul + isi notifikasi hasil akhir.
({String title, String body}) resultNotification(FootballMatch m) {
  final score = '${m.homeScore}-${m.awayScore}';
  final winner = m.homeScore! > m.awayScore!
      ? m.homeShort
      : m.homeScore! < m.awayScore!
          ? m.awayShort
          : 'Seri';
  return (
    title: '${m.homeShort} vs ${m.awayShort} selesai',
    body: '$score - $winner. Klasemen dan top skor sudah diperbarui.',
  );
}

/// Penjadwal notifikasi hasil akhir 15 menit setelah perkiraan akhir laga.
const resultNotifyAfterMinutes = 15;
const assumedMatchMinutes = 105;

/// Kapan notifikasi hasil sebuah laga seharusnya dibunyikan (UTC).
DateTime resultNotifyAt(FootballMatch m) => m.kickoffUtc.toUtc().add(
    const Duration(minutes: assumedMatchMinutes + resultNotifyAfterMinutes));

/// Jadwalkan notifikasi hasil untuk satu laga. Mengembalikan jumlah jadwal
/// yang benar-benar dibuat (0 bila waktunya sudah lewat).
Future<int> scheduleResultNotification(FootballMatch m) async {
  final when = resultNotifyAt(m);
  if (!when.isAfter(DateTime.now().toUtc())) return 0;

  final ok = await NotificationService.scheduleResult(
    matchId: m.id,
    whenUtc: when,
    title: 'Hasil akhir ${m.homeShort} vs ${m.awayShort}',
    body: 'Skor akhir sudah tersedia di Match Center.',
  );
  if (ok) {
    debugPrint('Notifikasi hasil dijadwalkan untuk ${m.homeShort} vs '
        '${m.awayShort} (${TimeUtils.formatHm(TimeUtils.wib(when))} WIB)');
  }
  return ok ? 1 : 0;
}

// C3: `pendingResultNotificationsProvider` dihapus. Tidak ada layar yang
// membacanya; notifikasi hasil ditangani `resultNotifierSyncProvider` di bawah.

/// Dipanggil setiap cache pertandingan berubah, untuk mengnotifikasi hasil baru.
final resultNotifierSyncProvider = Provider<void>((ref) {
  ref.listen(matchesProvider, (_, next) {
    final snapshot = next.valueOrNull;
    final data = snapshot?.data;
    if (data == null) return;
    final fav = ref.read(favoriteClubProvider);

    // N4: data contoh (tanpa FOOTBALL_API_KEY) tidak boleh memicu notifikasi.
    if (snapshot?.source == DataSource.sample) {
      debugPrint('Data contoh: penjadwalan notifikasi dilewati.');
      return;
    }

    final store = ref.read(notifiedStoreProvider);
    final done = store.load();
    final seeded = done.isEmpty;
    var changed = false;
    final scheduled = {...ref.read(_scheduledResultsProvider)};

    for (final m in data) {
      final sig = _sig(m);

      if (!m.isFinished || !m.hasScore) {
        // Laga belum selesai: pastikan pengingat hasil terjadwal satu kali saja
        // lewat signature (N5), bukan tiap perubahan data.
        if (!scheduled.containsKey(sig)) {
          scheduled[sig] = resultNotifyAt(m);
          scheduleResultNotification(m);
        }
        continue;
      }

      // N2: hasil lama harus ditandai "sudah dinotifikasi" tanpa ditampilkan.
      if (seeded) {
        if (done.add(m.id)) changed = true;
        continue;
      }

      if (done.contains(m.id)) continue;
      // Hanya laga tim favorit, dan hanya yang baru saja selesai.
      final recent = m.kickoffUtc
          .toUtc()
          .isAfter(DateTime.now().toUtc().subtract(resultNotifyMaxAge));
      if (fav == null || !m.involves(fav) || !recent) {
        if (done.add(m.id)) changed = true;
        continue;
      }

      final n = resultNotification(m);
      NotificationService.showResult(
          matchId: m.id, title: n.title, body: n.body);
      done.add(m.id);
      changed = true;
    }

    if (changed) {
      store.save(done);
      ref.read(notifiedMatchIdsProvider.notifier).state = done;
    }
    ref.read(_scheduledResultsProvider.notifier).state = scheduled;
  }, fireImmediately: true);
});

/// Bersihkan daftar notifikasi dari laga yang sudah tidak ada di jadwal.
final pruneNotifiedProvider = Provider<void>((ref) {
  ref.listen(matchesProvider, (_, next) {
    final matches = next.valueOrNull?.data ?? const <FootballMatch>[];
    final store = ref.read(notifiedStoreProvider);
    final live = matches.map((m) => m.id).toSet();
    final current = store.load();
    final kept = current.where(live.contains).toSet();
    if (kept.length == current.length) return;

    store.save(kept);
    ref.read(notifiedMatchIdsProvider.notifier).state = kept;
  }, fireImmediately: true);
});
