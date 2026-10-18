import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_rank.dart';

void main() {
  group('rankFor', () {
    test('returns the rank at each threshold boundary', () {
      expect(rankFor(0), PredictionRank.pemula);
      expect(rankFor(4), PredictionRank.pemula);
      expect(rankFor(5), PredictionRank.peramal);
      expect(rankFor(14), PredictionRank.peramal);
      expect(rankFor(15), PredictionRank.analis);
      expect(rankFor(29), PredictionRank.analis);
      expect(rankFor(30), PredictionRank.ahli);
      expect(rankFor(49), PredictionRank.ahli);
      expect(rankFor(50), PredictionRank.legenda);
      expect(rankFor(200), PredictionRank.legenda);
    });
  });

  test('returns the next rank until the highest rank', () {
    expect(nextRank(0), PredictionRank.peramal);
    expect(nextRank(5), PredictionRank.analis);
    expect(nextRank(50), isNull);
  });

  test('reports progress within the current tier', () {
    expect(progressToNext(0), 0);
    expect(progressToNext(10), 0.5);
    expect(progressToNext(50), 1);
  });

  test('lists crossed ranks in ascending order', () {
    expect(
        ranksCrossed(3, 16), [PredictionRank.peramal, PredictionRank.analis]);
    expect(ranksCrossed(5, 5), isEmpty);
  });
}
