/// Kota di Indonesia dengan perkiraan bujur dan zona waktu sipilnya.
///
/// Bujur dipakai untuk mengurutkan kota dari barat ke timur (fajar lebih
/// dulu di timur); zona waktu dipakai untuk menampilkan jam lokal saat
/// away day.
class IndoCity {
  /// Membuat entri kota.
  const IndoCity(this.name, this.lng, this.zone);

  /// Nama kota yang ditampilkan.
  final String name;

  /// Perkiraan bujur (derajat, positif = timur).
  final double lng;

  /// Zona waktu sipil: `WIB`, `WITA`, atau `WIT`.
  final String zone;
}

/// Daftar kota Indonesia yang ditampilkan, diurutkan dari barat ke timur.
///
/// Daftar ini statis (bukan dari API), jadi bisa dipakai tanpa jaringan.
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
