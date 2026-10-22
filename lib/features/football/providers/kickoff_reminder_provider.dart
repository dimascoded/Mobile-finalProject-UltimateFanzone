import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/utils/app_config.dart';
import '../../sos_emergency/data/notification_service.dart';
import '../data/football_repository.dart';
import '../data/models.dart';
import '../data/reminder_leads.dart';
import 'football_providers.dart';

/// Berapa menit sebelum kickoff pengingat ditampilkan. Bisa diturunkan saat
/// uji manual lewat `--dart-define=KICKOFF_REMINDER_MINUTES=2`.
const kickoffReminderMinutes = AppConfig.kickoffReminderMinutes;

/// Batas jumlah laga yang boleh punya pengingat. iOS hanya menerima 64
/// notifikasi terjadwal; dengan [maxReminderSlots] lead time per laga,
/// 10 laga x 3 slot = 30, masih jauh di bawah batas itu.
const maxKickoffReminders = 10;

/// Signature jadwal yang terakhir diproses, supaya tidak menjadwal ulang
/// event yang sama setiap kali provider dibangun ulang.
///
/// State di memori (bukan Hive): nilainya hanya bertahan selama aplikasi
/// hidup dan sengaja dibuat `StateProvider` biasa agar tidak ter-reset saat
/// provider lain dibangun ulang.
final _lastScheduledProvider = StateProvider<String>((ref) => '');

// ---------- Lead time pengingat (pilihan pengguna) ----------

/// Kunci Hive untuk lead time pengingat kickoff. Sengaja bukan kunci data
/// pengguna: pengaturan ini ikut bertahan saat logout.
const kickoffLeadsCacheKey = 'kickoff_reminder_leads';

/// Izin exact alarm diminta sekali saja (tanda 'exact_alarm_asked'), baik
/// saat lead time pertama kali disimpan maupun saat tombol Match Center
/// ditekan.
///
/// Efek samping: menulis penanda ke Hive `app_cache` (kunci
/// `exact_alarm_asked`) setelah permintaan, sehingga izin tidak ditanyakan
/// ulang tiap kali aplikasi dibuka. Fungsi ini idempoten dan aman dipanggil
/// dari mana saja.
Future<void> ensureExactAlarmPermissionAsked() async {
  if (HiveService.cache.get('exact_alarm_asked') == 'true') return;
  await NotificationService.requestExactAlarmPermission();
  await HiveService.cache.put('exact_alarm_asked', 'true');
}

/// Daftar lead time (menit, urut menurun) yang dipilih pengguna. Daftar kosong
/// berarti pengingat kickoff nonaktif.
///
/// State-nya `List<int>` hasil normalisasi [normalizeLeads]: nilai <= 0 atau
/// > 7 hari dibuang, duplikat dihapus, diurutkan menurun, dan dibatasi
/// maksimal 3 slot (harus sama dengan `NotificationService.kickoffSlotCount`).
/// Pilihan disimpan di Hive `app_cache` (kunci `kickoff_reminder_leads`) dan
/// sengaja bukan per pengguna, jadi pengaturan perangkat bertahan saat
/// logout.
class KickoffLeadsNotifier extends StateNotifier<List<int>> {
  KickoffLeadsNotifier() : super(_load());

  static List<int> _load() {
    final raw = HiveService.cache.get(kickoffLeadsCacheKey);
    // Kunci belum pernah disimpan -> pakai lead time bawaan.
    if (raw == null) return List<int>.of(defaultLeads);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List<int>.of(defaultLeads);
      return normalizeLeads(decoded.whereType<num>().map((e) => e.toInt()));
    } catch (_) {
      // Nilai rusak/bukan JSON: kembali ke bawaan.
      return List<int>.of(defaultLeads);
    }
  }

  /// Simpan lead time baru (di-normalisasi dulu) lalu minta izin exact alarm
  /// bila hasilnya tidak kosong.
  ///
  /// Menulis daftar hasil normalisasi ke Hive `app_cache` (kunci
  /// `kickoff_reminder_leads`). Bila daftar tidak kosong, izin exact alarm
  /// dipastikan sudah diminta lewat [ensureExactAlarmPermissionAsked] supaya
  /// notifikasi benar-benar berbunyi tepat waktu di Android 12+.
  Future<void> set(List<int> leads) async {
    final normalized = normalizeLeads(leads);
    if (!listEquals(state, normalized)) state = normalized;
    await HiveService.cache.put(kickoffLeadsCacheKey, jsonEncode(normalized));
    if (normalized.isNotEmpty) await ensureExactAlarmPermissionAsked();
  }

  /// Tambah satu lead time (menit) ke daftar yang ada.
  ///
  /// Setara memanggil [set] dengan daftar lama ditambah nilai baru; daftar
  /// dinormalisasi sehingga nilai tidak valid diabaikan dan batas 3 slot
  /// tetap berlaku. Efek samping: penulisan Hive + permintaan izin exact
  /// alarm.
  Future<void> add(int minutes) async => set([...state, minutes]);

  /// Hapus satu lead time (menit) dari daftar.
  ///
  /// Bila daftar menjadi kosong, pengingat kickoff otomatis nonaktif dan izin
  /// exact alarm tidak diminta ulang. Efek samping: penulisan Hive.
  Future<void> remove(int minutes) async => set([...state]..remove(minutes));

  /// Kembalikan lead time ke daftar bawaan (ikut `--dart-define`).
  ///
  /// Efek samping: penulisan Hive dan permintaan izin exact alarm bila
  /// hasilnya tidak kosong.
  Future<void> reset() async => set(defaultLeads);
}

/// Lead time pengingat kickoff milik pengguna.
///
/// StateProvider biasa (bukan `autoDispose`) supaya pilihan lead time tidak
/// hilang saat layar pengaturan ditutup; sumber penyimpanan ada di
/// [KickoffLeadsNotifier].
final kickoffLeadsProvider =
    StateNotifierProvider<KickoffLeadsNotifier, List<int>>(
        (ref) => KickoffLeadsNotifier());

// ---------- Sasaran pengingat ----------

/// Laga yang perlu pengingat: hanya yang memuat tim favorit, maksimal
/// [maxKickoffReminders] laga terdekat. Kosong bila tim favorit belum dipilih.
///
/// Fungsi murni (tanpa efek samping): menyaring laga berstatus `upcoming`
/// yang melibatkan tim favorit, mengurutkannya berdasarkan kickoff terdekat,
/// lalu mengambil maksimal 10 laga. Dipakai baik oleh penjadwal pengingat
/// kickoff maupun penjadwal notifikasi hasil akhir.
List<FootballMatch> reminderTargets(
  List<FootballMatch> matches,
  PlClub? favorite,
) {
  if (favorite == null) return const <FootballMatch>[];
  final now = DateTime.now().toUtc();
  final pool = matches
      .where((m) =>
          m.phaseAt(now) == MatchPhase.upcoming && m.involves(favorite))
      .toList()
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
  return pool.take(maxKickoffReminders).toList();
}

/// Signature jadwal yang terakhir diproses: lead time + daftar laga. Lead time
/// ikut dihitung supaya penggantian lead time selalu memicu penjadwalan ulang.
///
/// Fungsi murni; hasilnya disimpan di [_lastScheduledProvider] supaya jadwal
/// tidak dibuat dua kali untuk kombinasi lead time + daftar laga yang sama.
String _signature(List<FootballMatch> targets, List<int> leads) {
  final parts = targets.map((m) => '${m.id}@${m.kickoffUtc.toIso8601String()}');
  return '${leads.join(',')}|${parts.join('|')}';
}

/// Dijalankan sekali setelah cache pertandingan termuat, dan setiap kali tim
/// favorit atau lead time pengingat berubah (jadwal lama dibatalkan lalu
/// dibuat ulang).
///
/// Provider "seam" tanpa state: yang di dalamnya adalah effect — dia
/// memasang listener pada [matchesProvider], [favoriteClubProvider], dan
/// [kickoffLeadsProvider], lalu menjadwalkan/membatalkan notifikasi lokal
/// lewat `zonedSchedule`. Provider ini `autoDispose`, jadi seluruh listener
/// dibuang saat tidak ada lagi yang rebuilding; penjadwalan ulang yang
/// tertunda (unawaited) tetap aman karena penjadwalan tidak menyentuh
/// `state`.
///
/// Aturan yang berlaku: data contoh (tanpa `FOOTBALL_API_KEY`) tidak pernah
/// dijadwalkan, dan penjadwalan baru hanya dikirim SETELAH pembatalan slot
/// lama selesai supaya jadwal baru ikut terhapus.
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

    final leads = ref.read(kickoffLeadsProvider);
    final targets = reminderTargets(data, ref.read(favoriteClubProvider));
    final sig = _signature(targets, leads);
    if (ref.read(_lastScheduledProvider) == sig) return;
    ref.read(_lastScheduledProvider.notifier).state = sig;
    unawaited(scheduleReminders(targets, leads: leads));
  }

  /// Batalkan seluruh slot lama untuk [targets] dulu, baru susun ulang.
  /// `cancelKickoff` kini membatalkan tiga slot berurutan, jadi penjadwalan
  /// baru baru boleh dikirim setelah pembatalan selesai — kalau tidak,
  /// jadwal baru ikut terhapus.
  Future<void> cancelThenReschedule(List<FootballMatch> targets) async {
    try {
      await cancelReminders(targets);
    } finally {
      reschedule(ref.read(matchesProvider));
    }
  }

  ref.listen(matchesProvider, (_, next) => reschedule(next),
      fireImmediately: true);

  // Tim favorit diganti -> batalkan semua jadwal lama, lalu susun ulang.
  ref.listen(favoriteClubProvider, (prev, next) {
    final data = ref.read(matchesProvider).valueOrNull?.data;
    ref.read(_lastScheduledProvider.notifier).state = '';
    unawaited(cancelThenReschedule(data ?? const <FootballMatch>[]));
  });

  // Lead time diganti -> batalkan semua slot laga target (lead time lama
  // mungkin punya lebih banyak slot), lalu susun ulang dengan lead time baru.
  // Lead time kosong berarti pengingat nonaktif: cukup batalkan, lalu
  // scheduleReminders tidak menjadwalkan apa pun.
  ref.listen(kickoffLeadsProvider, (prev, next) {
    final data = ref.read(matchesProvider).valueOrNull?.data;
    final targets = reminderTargets(
        data ?? const <FootballMatch>[], ref.read(favoriteClubProvider));
    ref.read(_lastScheduledProvider.notifier).state = '';
    unawaited(cancelThenReschedule(targets));
  });
});

/// Batalkan pengingat kickoff untuk daftar [matches] yang diberikan
/// (seluruh slot tiap laga).
///
/// Membatalkan semua slot lead time tiap laga (slot 0..2) melalui
/// `NotificationService.cancelKickoff`; slot notifikasi hasil akhir tidak
/// disentuh. Efek samping: notifikasi lokal yang sudah terjadwal dibatalkan
/// di OS.
Future<void> cancelReminders(List<FootballMatch> matches) async {
  for (final m in matches) {
    await NotificationService.cancelKickoff(m.id);
  }
}

/// Dipanggil tombol "Atur pengingat" di Match Center. Mengembalikan jumlah
/// notifikasi yang berhasil dijadwalkan.
///
/// [minutesBefore] hanya override untuk uji; tanpa itu, lead time dibaca dari
/// pilihan pengguna di [kickoffLeadsProvider].
///
/// Mengembalikan 0 tanpa menjadwalkan apa pun bila: cache pertandingan belum
/// termuat, data yang dipakai adalah data contoh, daftar lead time kosong,
/// atau semua waktu bunyi sudah lewat. Efek samping: meminta izin exact
/// alarm (hanya sekali seumur perangkat) dan menjadwalkan notifikasi lokal
/// melalui `zonedSchedule`.
Future<int> scheduleRemindersForUpcoming(
  WidgetRef ref, {
  int? minutesBefore,
}) async {
  final snapshot = ref.read(matchesProvider).valueOrNull;
  if (snapshot == null) return 0;
  // N4: data contoh tidak pernah dijadwalkan.
  if (snapshot.source == DataSource.sample) {
    debugPrint('Data contoh: pengingat kickoff tidak dijadwalkan.');
    return 0;
  }
  final leads = minutesBefore != null
      ? normalizeLeads([minutesBefore])
      : ref.read(kickoffLeadsProvider);
  if (leads.isEmpty) {
    debugPrint('Lead time kosong: pengingat kickoff tidak dijadwalkan.');
    return 0;
  }
  // C5: izin exact alarm diminta sekali saja (lihat
  // [ensureExactAlarmPermissionAsked]), bukan tiap kali aplikasi dibuka.
  await ensureExactAlarmPermissionAsked();
  final targets =
      reminderTargets(snapshot.data, ref.read(favoriteClubProvider));
  return scheduleReminders(targets, leads: leads);
}

/// Jadwalkan seluruh slot pengingat untuk setiap laga di [targets] secara
/// paralel dan mengembalikan jumlah notifikasi yang benar-benar dibuat.
/// [leads] kosong -> tidak ada yang dijadwalkan (pengingat nonaktif).
///
/// Hanya lead time yang masih di masa depan yang dijadwalkan (lihat
/// `plannedReminders`). Setiap slot memakai id notifikasi sendiri
/// (`matchId * 10 + {1,3,4}`) supaya tidak saling menimpa, dan jadwal
/// dikirim lewat `NotificationService.scheduleKickoff` (zonedSchedule dengan
/// mode exact, ada fallback inexact bila izin exact alarm tidak ada).
///
/// Efek samping: membuat notifikasi terjadwal di OS. Tidak menyentuh state
/// Riverpod mana pun, jadi aman dipanggil dari provider `autoDispose`.
Future<int> scheduleReminders(
  List<FootballMatch> targets, {
  required List<int> leads,
}) async {
  final normalized = normalizeLeads(leads);
  if (targets.isEmpty || normalized.isEmpty) {
    debugPrint('Tidak ada pengingat yang dijadwalkan '
        '(laga: ${targets.length}, lead time: ${normalized.length}).');
    return 0;
  }
  final now = DateTime.now().toUtc();
  final jobs = <Future<bool>>[];
  for (final m in targets) {
    final planned = plannedReminders(m.kickoffUtc, normalized, now);
    for (final (slot, minutes, fireUtc) in planned) {
      jobs.add(NotificationService.scheduleKickoff(
        matchId: m.id,
        kickoffUtc: m.kickoffUtc,
        title: 'Kickoff ${m.homeShort} vs ${m.awayShort}',
        body: leadBody(minutes),
        slot: slot,
        fireUtc: fireUtc,
      ));
    }
  }
  final results = await Future.wait(jobs);
  final count = results.where((ok) => ok).length;
  debugPrint('Pengingat kickoff terjadwal: $count notifikasi dari '
      '${targets.length} laga');
  return count;
}
