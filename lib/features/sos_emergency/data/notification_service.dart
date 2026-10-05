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
    await _plugin
        .initialize(const InitializationSettings(android: android, iOS: ios));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    // C5: Android 12+ butuh izin "exact alarm" yang diminta terpisah dari
    // SCHEDULE_EXACT_ALARM di manifest. Tanpa ini zonedSchedule exact gagal dan
    // jatuh ke inexact, jadi pengingat bisa terlambat puluhan menit.
    await requestExactAlarmPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Minta izin exact alarm bila belum diberikan. Mengembalikan true bila
  /// aplikasi boleh menjadwalkan alarm tepat waktu, atau true juga di platform
  /// yang tidak punya konsep itu (mis. iOS).
  static Future<bool> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // bukan Android: tidak perlu izin
    try {
      final granted = await android.canScheduleExactNotifications();
      if (granted == true) return true;
      await android.requestExactAlarmsPermission();
      return await android.canScheduleExactNotifications() ?? false;
    } catch (e) {
      debugPrint('Gagal meminta izin exact alarm: $e');
      return false;
    }
  }

  // ---------- Slot id notifikasi ----------
  //
  // Satu laga punya DUA notifikasi (pengingat kickoff + pengingat hasil), jadi
  // keduanya harus memakai id berbeda agar tidak saling menimpa.
  // SOS memakai id 0.
  static const sosId = 0;

  /// Id notifikasi terjadwal untuk pengingat kickoff sebuah laga.
  static int kickoffId(int matchId) => matchId * 10 + 1;

  /// Id notifikasi terjadwal untuk pengingat hasil akhir sebuah laga.
  static int resultId(int matchId) => matchId * 10 + 2;

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

  /// Jadwalkan pengingat pada [when] (UTC). Mengembalikan false bila
  /// waktunya sudah lewat.
  static Future<bool> _scheduleAt(
    int id,
    DateTime when,
    String title,
    String body,
  ) async {
    if (!_tzReady) await init();
    if (!when.toUtc().isAfter(DateTime.now().toUtc())) return false;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _matchDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (e) {
      // Android 12+ bisa menolak exact alarm bila izin dicabut pengguna.
      debugPrint('zonedSchedule exact gagal, fallback inexact: $e');
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _matchDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    }
  }

  /// Jadwalkan pengingat kickoff. [minutesBefore] default 30 menit.
  /// Mengembalikan false bila waktunya sudah lewat.
  static Future<bool> scheduleKickoff({
    required int matchId,
    required DateTime kickoffUtc,
    required String title,
    required String body,
    int minutesBefore = 30,
  }) =>
      _scheduleAt(
          kickoffId(matchId),
          kickoffUtc.toUtc().subtract(Duration(minutes: minutesBefore)),
          title,
          body);

  /// Jadwalkan notifikasi hasil akhir (dipakai result_notification_provider).
  static Future<bool> scheduleResult({
    required int matchId,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) =>
      _scheduleAt(resultId(matchId), whenUtc.toUtc(), title, body);

  /// Batalkan kedua notifikasi milik sebuah laga.
  static Future<void> cancelMatch(int matchId) async {
    await _plugin.cancel(kickoffId(matchId));
    await _plugin.cancel(resultId(matchId));
  }

  /// Notifikasi hasil akhir langsung tampil (bukan terjadwal), mis. karena
  /// perkiraan akhir laga sudah lewat saat aplikasi dibuka.
  static Future<void> showResult({
    required int matchId,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      resultId(matchId),
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
    return _plugin.show(sosId, title, body, details);
  }
}
