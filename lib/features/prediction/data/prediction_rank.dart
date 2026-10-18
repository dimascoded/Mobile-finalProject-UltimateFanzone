enum PredictionRank {
  pemula('pemula', 'Pemula', 0),
  peramal('peramal', 'Peramal', 5),
  analis('analis', 'Analis', 15),
  ahli('ahli', 'Ahli', 30),
  legenda('legenda', 'Legenda', 50);

  const PredictionRank(this.key, this.name, this.min);

  final String key;
  final String name;
  final int min;
}

PredictionRank rankFor(int points) {
  for (final rank in PredictionRank.values.reversed) {
    if (points >= rank.min) return rank;
  }
  return PredictionRank.pemula;
}

PredictionRank? nextRank(int points) {
  for (final rank in PredictionRank.values) {
    if (rank.min > points) return rank;
  }
  return null;
}

double progressToNext(int points) {
  final current = rankFor(points);
  final next = nextRank(points);
  if (next == null) return 1;
  return ((points - current.min) / (next.min - current.min)).clamp(0.0, 1.0);
}

List<PredictionRank> ranksCrossed(int before, int after) =>
    PredictionRank.values
        .where((rank) => rank.min > before && rank.min <= after)
        .toList();
