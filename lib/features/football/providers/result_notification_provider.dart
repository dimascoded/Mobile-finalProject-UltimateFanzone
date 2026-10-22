import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/utils/time_utils.dart';
import '../../sos_emergency/data/notification_service.dart';
import '../data/football_repository.dart';
import '../data/models.dart';
import 'football_providers.dart';
import 'kickoff_reminder_provider.dart';

/// Batas usia hasil laga agar notifikasi tidak membanjiri pengguna.
/// Laga yang selesai lebih lama dari ini tidak dinotifikasi.
const resultNotifyMaxAge = Duration(hours: 6);

/// Id laga yang hasil akhirnya sudah pernah dinotifikasi.
///
/// State di memori (bukan Hive) yang dicerminkan dari daftar persisten di
/// [NotifiedStore]; dipakai UI untuk tahu laga mana yang sudah diberi tahu
/// pada sesi ini. StateProvider biasa agar tidak ter-reset saat provider lain
/// dibangun ulang.
final notifiedMatchIdsProvider = StateProvider<Set<int>>((ref) => const {});

/// Signature penjadwalan hasil agar tidak dijadwalkan ulang setiap data berubah:
/// `matchId@kickoffUtc`.
final _scheduledResultsProvider =
    StateProvider<Map<String, DateTime>>((ref) => const {});

/// Signature satu laga: `matchId@kickoffUtc` (waktu dalam UTC).
///
/// Fungsi murni; dipakai sebagai kunci di [_scheduledResultsProvider] supaya
/// satu laga hanya punya satu jadwal pengingat hasil.
String _sig(FootballMatch m) =>
    '${m.id}@${m.kickoffUtc.toUtc().toIso8601String()}';

/// Penyimpanan daftar id laga yang sudah dinotifikasi.
///
/// Dipersisten di Hive `app_cache` dengan kunci `notified_results` sebagai
/// JSON `List<int>` (format lama `'#1;#2;'` dibaca sebagai data rusak lalu
/// diabaikan). Kunci ini termasuk daftar data pengguna yang dihapus saat
/// logout lewat [AuthRepository.userDataKeys].
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
  ///
  /// Efek samping: menulis ulang Hive `app_cache` (kunci `notified_results`).
  Future<void> save(Set<int> ids) =>
      HiveService.cache.put(_key, jsonEncode(ids.toList()..sort()));
}

/// Penyedia tunggal [NotifiedStore] yang dipakai sinkronisasi notifikasi.
final notifiedStoreProvider = Provider((ref) => NotifiedStore());

/// Bangun judul + isi notifikasi hasil akhir.
///
/// Fungsi murni: judul memuat nama pendek kedua tim, isi memuat skor dan
/// pemenang (atau "Seri" bila imbang).
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
///
/// `assumedMatchMinutes` adalah asumsi durasi laga (105 menit) dipakai untuk
/// memperkirakan waktu selesai; angka tetap + 15 menit agar notifikasi
/// dijadwalkan cukup jauh setelah ada kemungkinan skor akhir tersedia.
const resultNotifyAfterMinutes = 15;
const assumedMatchMinutes = 105;

/// Isi pengingat hasil yang terjadwal. Sengaja netral: skor belum tentu sudah
/// tersedia saat notifikasi dibunyikan, jadi cukup arahkan ke Match Center.
const resultReminderBody =
    'Laga selesai. Buka Match Center untuk skor terbaru.';

/// Kapan notifikasi hasil sebuah laga seharusnya dibunyikan (UTC).
///
/// Fungsi murni: kickoff + durasi asumsi + jeda [resultNotifyAfterMinutes].
DateTime resultNotifyAt(FootballMatch m) => m.kickoffUtc.toUtc().add(
    const Duration(minutes: assumedMatchMinutes + resultNotifyAfterMinutes));

/// Jadwalkan notifikasi hasil untuk satu laga. Mengembalikan jumlah jadwal
/// yang benar-benar dibuat (0 bila waktunya sudah lewat).
///
/// Efek samping: membuat notifikasi terjadwal di OS lewat
/// `NotificationService.scheduleResult` (id notifikasi `matchId * 10 + 2`).
/// Tidak menyentuh state Riverpod.
Future<int> scheduleResultNotification(FootballMatch m) async {
  final when = resultNotifyAt(m);
  if (!when.isAfter(DateTime.now().toUtc())) return 0;

  final ok = await NotificationService.scheduleResult(
    matchId: m.id,
    whenUtc: when,
    title: 'Hasil akhir ${m.homeShort} vs ${m.awayShort}',
    body: resultReminderBody,
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
///
/// Provider "seam" tanpa state: isinya effect yang memasang listener pada
/// [matchesProvider] dan [favoriteClubProvider], lalu compleja tiga hal:
///
/// 1. Memastikan pengingat hasil terjadwal satu kali per laga (kunci
///    signature di [_scheduledResultsProvider]).
/// 2. Menampilkan notifikasi hasil akhir LANGSUNG (bukan terjadwal) untuk
///    laga tim favorit yang baru saja selesai — dibatasi umur
///    [resultNotifyMaxAge] (6 jam) supaya tidak membanjiri pengguna.
/// 3. Merekaman id liga yang sudah dinotifikasi ke Hive `app_cache` (kunci
///    `notified_results`) lewat [NotifiedStore].
///
/// Aturan yang berlaku: data contoh (tanpa `FOOTBALL_API_KEY`) tidak pernah
/// memicu notifikasi, dan pada proses pertama daftar kosong diperlakukan
/// sebagai "seed" — hasil lama ditandai sudah dinotifikasi tanpa
/// ditampilkan. Provider ini `autoDispose`, jadi listener dibuang otomatis
/// saat tidak dipakai; penjadwalan yang tertunda tidak menyentuh `state`
/// Riverpod sehingga aman setelah provider dibuang.
final resultNotifierSyncProvider = Provider<void>((ref) {
  void process(AsyncValue<FootballResult<List<FootballMatch>>> next) {
    final snapshot = next.valueOrNull;
    final data = snapshot?.data;
    if (data == null) return;
    final fav = ref.read(favoriteClubProvider);

    // N4: data contoh (tanpa FOOTBALL_API_KEY) tidak boleh memicu notifikasi.
    if (snapshot?.source == DataSource.sample) {
      debugPrint('Data contoh: penjadwalan notifikasi dilewati.');
      return;
    }

    // Pengingat hasil hanya untuk laga tim favorit, dengan kuota yang sama
    // seperti pengingat kickoff. Tanpa tim favorit tidak ada yang dijadwalkan.
    final targetIds = reminderTargets(data, fav).map((m) => m.id).toSet();

    final store = ref.read(notifiedStoreProvider);
    final done = store.load();
    final seeded = done.isEmpty;
    var changed = false;
    final scheduled = {...ref.read(_scheduledResultsProvider)};

    for (final m in data) {
      final sig = _sig(m);

      if (!m.isFinished || !m.hasScore) {
        // Laga belum selesai: pastikan pengingat hasil terjadwal satu kali saja
        // lewat signature (N5), dan hanya bila laga termasuk target.
        if (targetIds.contains(m.id) && !scheduled.containsKey(sig)) {
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
  }

  ref.listen(matchesProvider, (_, next) => process(next),
      fireImmediately: true);

  // Tim favorit diganti -> batalkan pengingat hasil yang bukan target lagi,
  // lalu susun ulang untuk tim favorit baru. Pembatalan di-await berurutan
  // sebelum penjadwalan agar tidak ada balapan dengan jadwal baru.
  ref.listen(favoriteClubProvider, (prev, next) async {
    final data = ref.read(matchesProvider).valueOrNull?.data;
    if (data == null) return;
    final targetIds = reminderTargets(data, next).map((m) => m.id).toSet();
    for (final sig in ref.read(_scheduledResultsProvider).keys) {
      final id = int.tryParse(sig.split('@').first);
      if (id == null || targetIds.contains(id)) continue;
      await NotificationService.cancelResult(id);
    }
    ref.read(_scheduledResultsProvider.notifier).state = const {};
    process(ref.read(matchesProvider));
  });
});

/// Bersihkan daftar notifikasi dari laga yang sudah tidak ada di jadwal.
///
/// Provider "seam" tanpa state: memasang listener pada [matchesProvider] dan
/// setiap ada perubahan, membandingkan daftar id liga yang tersimpan di Hive
/// `app_cache` (kunci `notified_results`) dengan id liga yang masih ada di
/// jadwal. Laga yang sudah tidak ada dibuang dari daftar.
///
/// Efek samping: menulis ulang Hive `notified_results` dan memperbarui
/// [notifiedMatchIdsProvider]. `autoDispose`, jadi listener dibuang otomatis
/// saat tidak dipakai.
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
