/// Peringkat pemain berdasarkan total poin prediksi.
///
/// Murni Dart tanpa I/O; poin dihitung dari blok rantai oleh
/// `predictionPointsProvider`. Lihat `docs/feature-map.md` (bagian prediction).
enum PredictionRank {
  pemula('pemula', 'Pemula', 0),
  peramal('peramal', 'Peramal', 5),
  analis('analis', 'Analis', 15),
  ahli('ahli', 'Ahli', 30),
  legenda('legenda', 'Legenda', 50);

  const PredictionRank(this.key, this.name, this.min);

  /// Kunci stabil untuk blok `rank:<key>` di rantai (jangan diubah).
  final String key;

  /// Nama yang ditampilkan ke pengguna.
  final String name;

  /// Poin minimum untuk mencapai peringkat ini.
  final int min;
}

/// Peringkat yang sesuai untuk [points] (peringkat tertinggi yang terpenuhi).
PredictionRank rankFor(int points) {
  for (final rank in PredictionRank.values.reversed) {
    if (points >= rank.min) return rank;
  }
  return PredictionRank.pemula;
}

/// Peringkat berikutnya setelah [points], atau null bila sudah di puncak
/// ([PredictionRank.legenda]).
PredictionRank? nextRank(int points) {
  for (final rank in PredictionRank.values) {
    if (rank.min > points) return rank;
  }
  return null;
}

/// Progres menuju peringkat berikutnya sebagai 0.0..1.0.
/// Mengembalikan 1 bila sudah di peringkat tertinggi.
double progressToNext(int points) {
  final current = rankFor(points);
  final next = nextRank(points);
  if (next == null) return 1;
  return ((points - current.min) / (next.min - current.min)).clamp(0.0, 1.0);
}

/// Peringkat yang terlewati saat poin naik dari [before] ke [after].
/// Dipakai untuk memicu kartu hadiah kenaikan peringkat.
List<PredictionRank> ranksCrossed(int before, int after) =>
    PredictionRank.values
        .where((rank) => rank.min > before && rank.min <= after)
        .toList();
