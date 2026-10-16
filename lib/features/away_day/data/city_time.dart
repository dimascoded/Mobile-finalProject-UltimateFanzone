import '../../football/data/models.dart';

/// Satu derajat bujur sama dengan 4 menit waktu surya (matahari rata-rata).
const _secondsPerDegree = 240;

/// Selisih waktu surya lokal terhadap UTC untuk bujur [lng].
///
/// Bujur timur bernilai positif, barat negatif. Contoh: 15 derajat timur
/// menghasilkan tepat satu jam.
Duration solarOffset(double lng) =>
    Duration(seconds: (lng * _secondsPerDegree).round());

/// Waktu surya lokal (mean solar time) untuk momen [utc] di bujur [lng].
DateTime solarTime(DateTime utc, double lng) => utc.add(solarOffset(lng));

/// Format selisih durasi dalam bahasa Indonesia.
///
/// Satuan paling berarti tidak diberi nol di depan, satuan di bawahnya
/// diberi dua digit. Contoh: "-8 mnt 48 dtk", "+7 j 07 mnt 24 dtk", "0 dtk".
String formatOffset(Duration d) {
  final total = d.inSeconds;
  if (total == 0) return '0 dtk';
  final sign = total < 0 ? '-' : '+';
  final abs = total.abs();
  final hours = abs ~/ 3600;
  final minutes = (abs % 3600) ~/ 60;
  final seconds = abs % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$sign$hours j ${two(minutes)} mnt ${two(seconds)} dtk';
  }
  if (minutes > 0) {
    return '$sign$minutes mnt ${two(seconds)} dtk';
  }
  return '$sign$seconds dtk';
}

/// Rata-rata bujur per nama kota (setelah di-trim) dari daftar klub.
///
/// Klub dengan nama kota kosong dilewati. Kota dengan beberapa klub memakai
/// rata-rata supaya satu kota hanya menghasilkan satu nilai.
Map<String, double> cityLongitudes(List<PlClub> clubs) {
  final sum = <String, double>{};
  final count = <String, int>{};
  for (final club in clubs) {
    final city = club.city.trim();
    if (city.isEmpty) continue;
    sum[city] = (sum[city] ?? 0) + club.lng;
    count[city] = (count[city] ?? 0) + 1;
  }
  return {
    for (final entry in sum.entries) entry.key: entry.value / count[entry.key]!,
  };
}

/// Kota di Indonesia dengan perkiraan bujur dan zona waktu sipilnya.
class IndoCity {
  const IndoCity(this.name, this.lng, this.zone);

  final String name;
  final double lng;
  final String zone;
}

/// Daftar kota Indonesia yang ditampilkan, diurutkan dari barat ke timur.
const indonesianCities = <IndoCity>[
  IndoCity('Jakarta', 106.85, 'WIB'),
  IndoCity('Bandung', 107.61, 'WIB'),
  IndoCity('Medan', 98.67, 'WIB'),
  IndoCity('Surabaya', 112.75, 'WIB'),
  IndoCity('Denpasar', 115.22, 'WITA'),
  IndoCity('Makassar', 119.42, 'WITA'),
  IndoCity('Balikpapan', 116.83, 'WITA'),
  IndoCity('Manado', 124.84, 'WITA'),
  IndoCity('Ambon', 128.18, 'WIT'),
  IndoCity('Jayapura', 140.72, 'WIT'),
];
