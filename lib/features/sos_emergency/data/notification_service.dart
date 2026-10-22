import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Layanan notifikasi lokal (kickoff, hasil akhir, dan SOS).
///
/// Dua channel Android dipakai: `match_channel` ("Jadwal Pertandingan") untuk
/// pengingat laga, dan `sos_channel` ("SOS Darurat") untuk keadaan darurat.
///
/// Skema id notifikasi (lihat bagian "Slot id notifikasi" di bawah):
/// satu liga punya beberapa slot, semua berbasis `matchId * 10` + offset,
/// sedangkan id `0` dicadangkan untuk SOS.
class NotificationService {
  /// Instans plugin notifikasi lokal (statis, dipakai bersama).
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Id channel Android untuk pengingat pertandingan.
  static const _matchChannelId = 'match_channel';

  /// Id channel Android untuk notifikasi SOS.
  static const _sosChannelId = 'sos_channel';

  /// True setelah zona waktu berhasil diinisialisasi.
  static bool _tzReady = false;

  /// Inisialisasi zona waktu dan plugin notifikasi.
  ///
  /// Zona waktu lokal diambil dari perangkat (supaya jadwal ikut waktu
  /// pengguna), dengan fallback `Asia/Jakarta` bila pembacaan zona gagal.
  /// Sekaligus meminta izin notifikasi di Android dan iOS.
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
  // Satu laga punya minimal DUA notifikasi (pengingat kickoff + pengingat
  // hasil), dan pengingat kickoff kini boleh punya sampai [kickoffSlotCount]
  // slot lead time. Semuanya harus memakai id berbeda agar tidak saling
  // menimpa. SOS memakai id 0.
  //
  // Tata letak per laga: `matchId * 10` + {1, 3, 4} = slot kickoff 0..2,
  // + 2 = hasil akhir, + 0 dan + 5..9 tidak dipakai.
  //
  /// Id notifikasi khusus SOS (dipesan, tidak pernah dipakai slot laga).
  static const sosId = 0;

  /// Jumlah slot pengingat kickoff per laga. Harus sama dengan
  /// `maxReminderSlots` di reminder_leads.dart.
  static const kickoffSlotCount = 3;

  /// Id notifikasi terjadwal untuk pengingat kickoff sebuah laga (slot 0).
  ///
  /// Rumus: `matchId * 10 + 1`.
  static int kickoffId(int matchId) => matchId * 10 + 1;

  /// Id notifikasi terjadwal untuk pengingat kickoff pada [slot] (0..2).
  ///
  /// Slot 0 = [kickoffId]; slot 1 dan 2 sengaja melompati +2 karena angka
  /// itu milik [resultId]. Rumus lengkapnya `matchId * 10 + {1, 3, 4}`.
  static int kickoffIdForSlot(int matchId, int slot) => switch (slot) {
        1 => matchId * 10 + 3,
        2 => matchId * 10 + 4,
        _ => kickoffId(matchId),
      };

  /// Id notifikasi terjadwal untuk pengingat hasil akhir sebuah laga.
  ///
  /// Rumus: `matchId * 10 + 2`.
  static int resultId(int matchId) => matchId * 10 + 2;

  /// Detail notifikasi untuk channel "Jadwal Pertandingan".
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
  ///
  /// Memakai mode `exactAllowWhileIdle`; bila Android menolak (mis. izin
  /// exact alarm dicabut pengguna), otomatis turun ke `inexactAllowWhileIdle`
  /// supaya pengingat tetap terkirim.
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

  /// Jadwalkan pengingat kickoff pada slot [slot]. Waktu bunyi dihitung dari
  /// [kickoffUtc] dikurangi [minutesBefore], kecuali [fireUtc] diberikan
  /// (dipakai lead time yang sudah dihitung `plannedReminders`).
  /// Mengembalikan false bila waktunya sudah lewat.
  ///
  /// Id notifikasi memakai [kickoffIdForSlot], jadi setiap slot lead time punya
  /// notifikasi sendiri dan tidak saling menimpa.
  static Future<bool> scheduleKickoff({
    required int matchId,
    required DateTime kickoffUtc,
    required String title,
    required String body,
    int minutesBefore = 30,
    int slot = 0,
    DateTime? fireUtc,
  }) =>
      _scheduleAt(
        kickoffIdForSlot(matchId, slot),
        fireUtc?.toUtc() ??
            kickoffUtc.toUtc().subtract(Duration(minutes: minutesBefore)),
        title,
        body,
      );

  /// Jadwalkan notifikasi hasil akhir (dipakai result_notification_provider).
  ///
  /// Memakai id [resultId] (`matchId * 10 + 2`) yang berbeda dari slot
  /// pengingat kickoff.
  static Future<bool> scheduleResult({
    required int matchId,
    required DateTime whenUtc,
    required String title,
    required String body,
  }) =>
      _scheduleAt(resultId(matchId), whenUtc.toUtc(), title, body);

  /// Batalkan seluruh slot pengingat kickoff milik sebuah laga (semua lead
  /// time). Tidak menyentuh [resultId].
  static Future<void> cancelKickoff(int matchId) async {
    for (var slot = 0; slot < kickoffSlotCount; slot++) {
      await _plugin.cancel(kickoffIdForSlot(matchId, slot));
    }
  }

  /// Batalkan hanya notifikasi pengingat hasil milik sebuah laga.
  static Future<void> cancelResult(int matchId) =>
      _plugin.cancel(resultId(matchId));

  /// Batalkan kedua notifikasi milik sebuah laga.
  static Future<void> cancelMatch(int matchId) async {
    await cancelKickoff(matchId);
    await cancelResult(matchId);
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

  /// Tampilkan notifikasi SOS langsung (bukan terjadwal) di channel
  /// "SOS Darurat" dengan id [sosId].
  ///
  /// Isi notifikasi ini hanya koordinat lokasi di perangkat; aplikasi tidak
  /// punya backend pengirim, jadi pesan tidak terkirim ke siapa pun. Nomor
  /// darurat UK (999/112) ditampilkan terpisah di layar SOS.
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
