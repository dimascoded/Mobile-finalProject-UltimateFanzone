import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/sync/data/sync_models.dart';

void main() {
  test('Sync merge: remote row yang dihapus tidak diadopsi kembali', () async {
    final remoteRow = {
      'matchId': 42,
      'homeScore': 2,
      'awayScore': 1,
      'salt': 's',
      'commit': 'c',
      'createdAt': '2026-08-15T14:00:00Z',
    };
    final merged = mergePredictions(
      const [],
      [remoteRow],
      deletedMatchIds: {42},
    );
    expect(merged, isEmpty);
  });

  test('Sync merge: lokal yang dihapus tidak ikut dikembalikan', () async {
    final local = [
      Prediction(
        matchId: 42,
        homeScore: 2,
        awayScore: 1,
        salt: 's',
        commit: 'c',
        createdAt: DateTime.utc(2026, 8, 15),
      ),
    ];
    final merged = mergePredictions(local, [], deletedMatchIds: {42});
    expect(merged, isEmpty);
  });

  test('partitionDeletions memisahkan score_predictions dan away_day_expenses',
      () async {
    final part = partitionDeletions([
      (collection: 'score_predictions', itemId: '42'),
      (collection: 'score_predictions', itemId: 'abc'), // tidak valid int
      (collection: 'away_day_expenses', itemId: 'exp-1'),
      (collection: 'unknown', itemId: 'x'),
    ]);
    expect(part.predictionMatchIds.contains(42), isTrue);
    expect(part.predictionMatchIds.length, 1);
    expect(part.expenseDeletions.length, 1);
  });

  test('prediksi yang dihapus tidak dikirim ulang ke cloud', () async {
    final deleted = Prediction(
      matchId: 42,
      homeScore: 2,
      awayScore: 1,
      salt: 's',
      commit: 'c',
      createdAt: DateTime.utc(2026, 8, 15),
    );
    final kept = Prediction(
      matchId: 7,
      homeScore: 0,
      awayScore: 0,
      salt: 's2',
      commit: 'c2',
      createdAt: DateTime.utc(2026, 8, 15),
    );
    final merged = mergePredictions([deleted, kept], const [],
        deletedMatchIds: {42});
    final payload = predictionsToSync(merged, const []);
    expect(payload.map((p) => p['matchId']), [7]);
  });
}
