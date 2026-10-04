import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _matchChannelId = 'match_channel';
  static const _sosChannelId = 'sos_channel';

  static bool _tzReady = false;

  static Future<void> init() async {
    // timezone harus diinisialisasi sebelum zonedSchedule dipakai.
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      try {
        // Pakai zona perangkat supaya jadwal ikut waktu lokal pengguna.
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name.identifier));
      } catch (e) {
        debugPrint('Gagal membaca zona perangkat, fallback Asia/Jakarta: $e');
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      }
      _tzReady = true;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Slot id memakai match.id (int) langsung, jadi stabil dan tidak bentrok.
  static int _slotId(int matchId) => matchId;

  static NotificationDetails _matchDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _matchChannelId,
          'Jadwal Pertandingan',
          channelDescription: 'Pengingat kickoff dan hasil akhir',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Jadwalkan pengingat kickoff. [minutesBefore] default 30 menit.
  /// Mengembalikan false bila waktunya sudah lewat.
  static Future<bool> scheduleKickoff({
    required int matchId,
    required DateTime kickoffUtc,
    required String title,
    required String body,
    int minutesBefore = 30,
  }) async {
    if (!_tzReady) await init();
    final when = kickoffUtc.toUtc().subtract(Duration(minutes: minutesBefore));
    if (!when.isAfter(DateTime.now().toUtc())) return false;

    try {
      await _plugin.zonedSchedule(
        _slotId(matchId),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _matchDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      // Android 12+ bisa menolak exact alarm bila izin dicabut pengguna.
      debugPrint('zonedSchedule exact gagal, fallback inexact: $e');
      await _plugin.zonedSchedule(
        _slotId(matchId),
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _matchDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    }
  }

  static Future<void> cancelMatch(int matchId) => _plugin.cancel(_slotId(matchId));

  /// Notifikasi hasil akhir (dipanggil begitu status jadi FINISHED).
  static Future<void> showResult({
    required int matchId,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      _slotId(matchId),
      title,
      body,
      _matchDetails(),
    );
  }

  static Future<void> show(String title, String body) {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _sosChannelId,
        'SOS Darurat',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    return _plugin.show(0, title, body, details);
  }
}