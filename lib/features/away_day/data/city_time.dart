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
