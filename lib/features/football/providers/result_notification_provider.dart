import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/utils/time_utils.dart';
import '../../sos_emergency/data/notification_service.dart';
import '../data/models.dart';
import 'football_providers.dart';

/// Id laga yang hasil akhirnya sudah pernah dinotifikasi, supaya tidak
/// muncul berulang setiap aplikasi dibuka.
final _notifiedProvider = StateProvider<String>((ref) => '');

class NotifiedStore {
  static const _key = 'notified_results';

  String load() => HiveService.cache.get(_key) ?? '';

  Future<void> save(String v) => HiveService.cache.put(_key, v);
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

/// Menjadwalkan pengingat hasil akhir 15 menit setelah perkiraan akhir laga.
/// Kalau kickoff + 105 menit + 15 menit sudah lewat, notifikasi langsung
/// ditampilkan agar pengguna tidak perlu menunggu.
const resultNotifyAfterMinutes = 15;
const assumedMatchMinutes = 105;

Future<void> scheduleResultNotification(FootballMatch m) async {
  final wib = TimeUtils.wib(m.kickoffUtc);
  final predictedEndUtc = m.kickoffUtc.add(const Duration(minutes: assumedMatchMinutes));
  final when = predictedEndUtc.add(const Duration(minutes: resultNotifyAfterMinutes));

  if (!when.isAfter(DateTime.now().toUtc())) {
    final n = resultNotification(m);
    await NotificationService.showResult(matchId: m.id, title: n.title, body: n.body);
    return;
  }
  await NotificationService.scheduleKickoff(
    matchId: m.id,
    kickoffUtc: when,
    title: 'Hasil akhir ${m.homeShort} vs ${m.awayShort}',
    body: 'Skor akhir sudah tersedia di Match Center.',
    minutesBefore: 0,
  );
  debugPrint('Notifikasi hasil dijadwalkan untuk ${m.homeShort} vs ${m.awayShort} (${TimeUtils.formatHm(wib)} WIB)');
}

/// Daftar laga yang hasil akhirnya sudah finished tapi belum dinotifikasi.
final pendingResultNotificationsProvider =
    Provider<List<FootballMatch>>((ref) {
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final done = ref.read(_notifiedProvider);
  return matches
      .where((m) => m.isFinished && m.hasScore && !done.contains('#${m.id};'))
      .toList();
});

/// Dipanggil setiap cache pertandingan berubah, untuk mengnotifikasi hasil baru.
final resultNotifierSyncProvider = Provider<void>((ref) {
  ref.listen(matchesProvider, (_, next) {
    final data = next.valueOrNull?.data;
    if (data == null) return;
    final store = ref.read(notifiedStoreProvider);
    var done = store.load();
    var changed = false;

    for (final m in data) {
      final token = '#${m.id};';
      if (done.contains(token)) continue;
      if (m.isFinished && m.hasScore) {
        final n = resultNotification(m);
        NotificationService.showResult(matchId: m.id, title: n.title, body: n.body);
        done += token;
        changed = true;
      } else if (!m.isFinished && m.kickoffUtc.isAfter(DateTime.now().toUtc())) {
        // Laga belum main: ensure pengingat hasil terjadwal.
        scheduleResultNotification(m);
      }
    }
    if (changed) {
      store.save(done);
      ref.read(_notifiedProvider.notifier).state = done;
    }
  }, fireImmediately: true);
});

/// Bersihkan daftar notifikasi dari laga yang sudah tidak ada di jadwal.
final pruneNotifiedProvider = Provider<void>((ref) {
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final store = ref.read(notifiedStoreProvider);
  final live = matches.map((m) => '#${m.id};').toSet();
  final kept = store
      .load()
      .split(';')
      .where((t) => t.isNotEmpty && live.contains(t))
      .toList();
  final next = kept.isEmpty ? '' : '${kept.join(';')};';
  if (next != store.load()) {
    store.save(next);
    ref.read(_notifiedProvider.notifier).state = next;
  }
});
