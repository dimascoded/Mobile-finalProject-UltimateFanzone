import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/time_utils.dart';

export '../../away_day/data/city_time.dart' show indonesianCities, IndoCity;

// ---------- Jam dunia (rubrik: WIB / WITA / WIT / London) ----------

/// Zona waktu yang dipakai label jam dunia.
///
/// State lokal UI dengan `autoDispose`; nilai bawaan `'WIB'`.
final awayDayClockZoneProvider =
    StateProvider.autoDispose<String>((ref) => 'WIB');

/// Kota Indonesia yang dipilih; memilih kota menetapkan zona waktunya.
///
/// State lokal UI dengan `autoDispose`; null berarti belum ada pilihan
/// manual sehingga zona mengikuti [awayDayClockZoneProvider].
final awayDayClockIndoCityProvider =
    StateProvider.autoDispose<String?>((ref) => null);

/// Semua klub Premier League berbasis di Inggris, jadi zona yang relevan adalah
/// WIB, WITA, WIT, dan London (Europe/London, DST ikut dihitung oleh TimeUtils).
///
/// Provider stream `autoDispose`: memancarkan peta zona -> waktu lokal setiap
/// detik, dan berhenti otomatis saat tidak ada layar yang menonton (hemat
/// baterai). Perhitungan memakai satu titik waktu UTC yang sama untuk semua
/// zona, jadi jam di empat kota selalu konsisten. Tanpa efek samping.
final worldClockProvider =
    StreamProvider.autoDispose<Map<String, DateTime>>((ref) async* {
  while (true) {
    final utc = TimeUtils.nowUtc();
    yield {
      'WIB': TimeUtils.wib(utc),
      'WITA': TimeUtils.wita(utc),
      'WIT': TimeUtils.wit(utc),
      'London': TimeUtils.london(utc),
    };
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});
