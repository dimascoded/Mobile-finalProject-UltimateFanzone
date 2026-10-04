/// Kalkulasi waktu global murni lokal (tanpa API internet), termasuk aturan DST.
class TimeUtils {
  static DateTime nowUtc() => DateTime.now().toUtc();

  // Zona wajib rubrik
  static DateTime wib(DateTime utc) => utc.add(const Duration(hours: 7));
  static DateTime wita(DateTime utc) => utc.add(const Duration(hours: 8));
  static DateTime wit(DateTime utc) => utc.add(const Duration(hours: 9));
  static DateTime london(DateTime utc) => zoneTime(utc, 0, 'eu');

  /// Waktu lokal suatu zona: offset standar + 1 jam jika DST aktif.
  /// rule: 'none' | 'eu' | 'us' | 'au'
  static DateTime zoneTime(DateTime utc, int baseOffset, String rule) =>
      utc.add(Duration(hours: baseOffset + (isDst(utc, rule) ? 1 : 0)));

  static bool isDst(DateTime utc, String rule) {
    final y = utc.year;
    switch (rule) {
      case 'eu': // terakhir Minggu Maret s/d terakhir Minggu Oktober, 01:00 UTC
        final start = lastSunday(y, 3).add(const Duration(hours: 1));
        final end = lastSunday(y, 10).add(const Duration(hours: 1));
        return !utc.isBefore(start) && utc.isBefore(end);
      case 'us': // Minggu ke-2 Maret 07:00 UTC s/d Minggu ke-1 Nov 06:00 UTC (EST -5)
        final start = nthSunday(y, 3, 2).add(const Duration(hours: 7));
        final end = nthSunday(y, 11, 1).add(const Duration(hours: 6));
        return !utc.isBefore(start) && utc.isBefore(end);
      case 'au': // Sydney (belahan selatan): Minggu ke-1 Okt s/d Minggu ke-1 April, 16:00 UTC hari Sabtu sebelumnya
        final start = nthSunday(y, 10, 1).subtract(const Duration(hours: 8));
        final end = nthSunday(y, 4, 1).subtract(const Duration(hours: 8));
        return !utc.isBefore(start) || utc.isBefore(end);
      default:
        return false;
    }
  }

  static DateTime nthSunday(int year, int month, int n) {
    var d = DateTime.utc(year, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (n - 1)));
  }

  static DateTime lastSunday(int year, int month) {
    var d = DateTime.utc(year, month + 1, 0); // hari terakhir bulan
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  static const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  /// Contoh: "Sab, 04 Okt"
  static String formatDate(DateTime t) =>
      '${_days[t.weekday - 1]}, ${t.day.toString().padLeft(2, '0')} ${_months[t.month - 1]}';

  /// Contoh: "23:30"
  static String formatHm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Contoh: "2 hr 03 j 15 m" atau "01:02:03"; negatif = sudah mulai.
  static String formatCountdown(Duration d) {
    if (d.isNegative) return 'Sudah dimulai';
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inDays > 0) {
      return '${d.inDays} hr ${two(d.inHours % 24)} j ${two(d.inMinutes % 60)} m';
    }
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  static String format(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
