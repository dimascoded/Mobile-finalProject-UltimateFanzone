import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../sos_emergency/data/notification_service.dart';
import '../data/football_repository.dart';
import '../data/models.dart';
import 'football_providers.dart';

/// Berapa menit sebelum kickoff pengingat ditampilkan. Bisa diturunkan saat
/// uji manual lewat `--dart-define=KICKOFF_REMINDER_MINUTES=2`.
const kickoffReminderMinutes = AppConfig.kickoffReminderMinutes;

/// Batas jumlah pengingat yang dijadwalkan. iOS hanya menerima 64 notifikasi
/// terjadwal, jadi kita bertahan jauh di bawah batas itu.
const maxKickoffReminders = 20;

/// Signature jadwal yang terakhir diproses, supaya tidak menjadwal ulang
/// event yang sama setiap kali provider dibangun ulang.
final _lastScheduledProvider = StateProvider<String>((ref) => '');

/// Laga yang perlu pengingat: hanya yang memuat tim favorit, maksimal
/// [maxKickoffReminders] laga terdekat. Kosong bila tim favorit belum dipilih.
List<FootballMatch> reminderTargets(
  List<FootballMatch> matches,
  PlClub? favorite,
) {
  if (favorite == null) return const <FootballMatch>[];
  final now = DateTime.now().toUtc();
  final pool = matches
      .where((m) =>
          !m.isFinished && m.involves(favorite) && m.kickoffUtc.isAfter(now))
      .toList()
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
  return pool.take(maxKickoffReminders).toList();
}

String _signature(List<FootballMatch> targets, int minutesBefore) {
  final parts = targets.map((m) => '${m.id}@${m.kickoffUtc.toIso8601String()}');
  return '$minutesBefore|${parts.join('|')}';
}

/// Dijalankan sekali setelah cache pertandingan termuat, dan setiap kali tim
/// favorit berubah (N3: jadwal lama dibatalkan lalu dibuat ulang).
final kickoffReminderSyncProvider = Provider<void>((ref) {
  void reschedule(AsyncValue<FootballResult<List<FootballMatch>>> next) {
    final snapshot = next.valueOrNull;
    final data = snapshot?.data;
    if (data == null) return;

    // N4: tanpa FOOTBALL_API_KEY semua data adalah contoh -> jangan jadwalkan.
    if (snapshot?.source == DataSource.sample) {
      debugPrint('Data contoh: pengingat kickoff tidak dijadwalkan.');
      return;
    }

    final targets = reminderTargets(data, ref.read(favoriteClubProvider));
    final sig = _signature(targets, kickoffReminderMinutes);
    if (ref.read(_lastScheduledProvider) == sig) return;
    ref.read(_lastScheduledProvider.notifier).state = sig;
    unawaited(
        scheduleReminders(targets, minutesBefore: kickoffReminderMinutes));
  }

  ref.listen(matchesProvider, (_, next) => reschedule(next),
      fireImmediately: true);

  // Tim favorit diganti -> batalkan semua jadwal lama, lalu susun ulang.
  ref.listen(favoriteClubProvider, (prev, next) {
    final data = ref.read(matchesProvider).valueOrNull?.data;
    ref.read(_lastScheduledProvider.notifier).state = '';
    unawaited(cancelReminders(data ?? const <FootballMatch>[]));
    reschedule(ref.read(matchesProvider));
  });
});

/// Batalkan pengingat kickoff untuk daftar [matches] yang diberikan.
Future<void> cancelReminders(List<FootballMatch> matches) async {
  for (final m in matches) {
    await NotificationService.cancelKickoff(m.id);
  }
}

/// Dipanggil tombol "Atur pengingat" di Match Center. Mengembalikan jumlah
/// pengingat yang berhasil dijadwalkan.
Future<int> scheduleRemindersForUpcoming(
  WidgetRef ref, {
  int minutesBefore = kickoffReminderMinutes,
}) async {
  final snapshot = ref.read(matchesProvider).valueOrNull;
  if (snapshot == null) return 0;
  // N4: data contoh tidak pernah dijadwalkan.
  if (snapshot.source == DataSource.sample) {
    debugPrint('Data contoh: pengingat kickoff tidak dijadwalkan.');
    return 0;
  }
  // C5: izin exact alarm diminta sekali saja, saat pengguna menekan tombol
  // pengingat, bukan tiap kali aplikasi dibuka.
  if (HiveService.cache.get('exact_alarm_asked') != 'true') {
    await NotificationService.requestExactAlarmPermission();
    await HiveService.cache.put('exact_alarm_asked', 'true');
  }
  final targets =
      reminderTargets(snapshot.data, ref.read(favoriteClubProvider));
  return scheduleReminders(targets, minutesBefore: minutesBefore);
}

/// Jadwalkan [targets] secara paralel dan mengembalikan jumlah berhasil.
Future<int> scheduleReminders(
  List<FootballMatch> targets, {
  required int minutesBefore,
}) async {
  if (targets.isEmpty) {
    debugPrint('Tidak ada pengingat yang dijadwalkan (tim favorit kosong).');
    return 0;
  }
  final results = await Future.wait(targets.map((m) {
    return NotificationService.scheduleKickoff(
      matchId: m.id,
      kickoffUtc: m.kickoffUtc,
      title: 'Kickoff ${m.homeShort} vs ${m.awayShort}',
      body: 'Mulai dalam $minutesBefore menit',
      minutesBefore: minutesBefore,
    );
  }));
  final count = results.where((ok) => ok).length;
  debugPrint('Pengingat kickoff terjadwal: $count dari ${targets.length} laga');
  return count;
}
