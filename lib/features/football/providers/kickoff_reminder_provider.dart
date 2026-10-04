import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sos_emergency/data/notification_service.dart';
import '../data/models.dart';
import 'football_providers.dart';

/// Berapa menit sebelum kickoff pengingat ditampilkan.
const kickoffReminderMinutes = 30;

/// Signature jadwal yang terakhir diproses, supaya tidak menjadwal ulang
/// event yang sama setiap kali provider dibangun ulang.
final _lastScheduledProvider = StateProvider<String>((ref) => '');

String _signature(List<FootballMatch> matches, int minutesBefore) {
  final now = DateTime.now().toUtc();
  final parts = matches
      .where((m) => !m.isFinished && m.kickoffUtc.isAfter(now))
      .map((m) => '${m.id}@${m.kickoffUtc.toIso8601String()}');
  return '$minutesBefore|${parts.join('|')}';
}

/// Dijalankan sekali setelah cache pertandingan termuat.
final kickoffReminderSyncProvider = Provider<void>((ref) {
  ref.listen(matchesProvider, (_, next) {
    final data = next.valueOrNull?.data;
    if (data == null) return;
    final sig = _signature(data, kickoffReminderMinutes);
    if (ref.read(_lastScheduledProvider) == sig) return;
    ref.read(_lastScheduledProvider.notifier).state = sig;
    unawaited(_scheduleAll(data, minutesBefore: kickoffReminderMinutes));
  }, fireImmediately: true);
});

/// Dipanggil tombol "Atur pengingat" di Match Center. Mengembalikan jumlah
/// pengingat yang berhasil dijadwalkan.
Future<int> scheduleRemindersForUpcoming(
  WidgetRef ref, {
  int minutesBefore = kickoffReminderMinutes,
}) async {
  final data = ref.read(matchesProvider).valueOrNull?.data;
  if (data == null) return 0;
  return _scheduleAll(data, minutesBefore: minutesBefore);
}

Future<int> _scheduleAll(List<FootballMatch> matches, {required int minutesBefore}) async {
  final now = DateTime.now().toUtc();
  final upcoming = matches
      .where((m) => !m.isFinished && m.kickoffUtc.isAfter(now))
      .toList()
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

  var count = 0;
  for (final m in upcoming) {
    final ok = await NotificationService.scheduleKickoff(
      matchId: m.id,
      kickoffUtc: m.kickoffUtc,
      title: 'Kickoff ${m.homeShort} vs ${m.awayShort}',
      body: 'Liga Inggris - mulai dalam $minutesBefore menit',
      minutesBefore: minutesBefore,
    );
    if (ok) count++;
  }
  debugPrint('Pengingat kickoff terjadwal: $count dari ${upcoming.length} laga');
  return count;
}