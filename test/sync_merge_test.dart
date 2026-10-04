import 'package:flutter_test/flutter_test.dart';
import 'package:premiere_league_fan_assistant/features/away_day/data/away_day_repository.dart';
import 'package:premiere_league_fan_assistant/features/prediction/data/prediction_repository.dart';
import 'package:premiere_league_fan_assistant/features/sync/data/sync_models.dart';

AwayDayExpense expense(String title, {double gbp = 10, DateTime? at}) => AwayDayExpense(
      title: title,
      amountGbp: gbp,
      amountIdr: gbp * 20000,
      category: AwayDayCategory.tiket,
      date: at ?? DateTime.utc(2026, 8, 15, 14),
    );

Prediction prediction(int matchId, int home, int away) => Prediction(
      matchId: matchId,
      homeScore: home,
      awayScore: away,
      salt: 'salt$matchId',
      commit: 'commit$matchId',
    );

void main() {
  group('payload expense', () {
    test('id expense_follows tanggal ISO', () {
      final at = DateTime.utc(2026, 8, 15, 14, 30);
      expect(expenseToJson(expense('Tiket', at: at))['id'], at.toIso8601String());
    });

    test('kirim kedua mata uang dan kategori', () {
      final j = expenseToJson(expense('Tiket', gbp: 45));
      expect(j['amountGbp'], 45.0);
      expect(j['amountIdr'], 900000.0);
      expect(j['category'], 'tiket');
    });

    test('round trip json tidak mengubah data', () {
      final asli = expense('Hotel', gbp: 120);
      final kembali = expenseFromJson(expenseToJson(asli));
      expect(kembali.title, 'Hotel');
      expect(kembali.amountGbp, 120.0);
      expect(kembali.category, AwayDayCategory.tiket);
      expect(kembali.id, asli.id);
    });

    test('kategori tidak dikenal jatuh ke lainnya', () {
      final j = expenseToJson(expense('X'))..['category'] = 'entah';
      expect(expenseFromJson(j).category, AwayDayCategory.lainnya);
    });
  });

  group('payload prediksi', () {
    test('bawa matchId, skor, salt, dan commit', () {
      final j = predictionToJson(prediction(7001, 2, 1));
      expect(j['matchId'], 7001);
      expect(j['homeScore'], 2);
      expect(j['awayScore'], 1);
      expect(j['salt'], 'salt7001');
      expect(j['commit'], 'commit7001');
    });

    test('round trip json tidak mengubah data', () {
      final kembali = predictionFromJson(predictionToJson(prediction(42, 0, 3)));
      expect(kembali.matchId, 42);
      expect(kembali.homeScore, 0);
      expect(kembali.awayScore, 3);
      expect(kembali.salt, 'salt42');
    });
  });

  group('merge expense', () {
    test('gabung isi lokal dan server tanpa duplikat', () {
      final lokal = [
        expense('Tiket', at: DateTime.utc(2026, 8, 15, 14)),
        expense('Hotel', at: DateTime.utc(2026, 8, 15, 20)),
      ];
      final remote = [
        expenseToJson(expense('Tiket', at: DateTime.utc(2026, 8, 15, 14))),
        expenseToJson(expense('Makan', at: DateTime.utc(2026, 8, 16))),
      ];
      final hasil = mergeExpenses(lokal, remote);
      expect(hasil.length, 3, reason: 'dua lokal + satu dari server');
    });

    test('id sama tidak digandakan', () {
      final at = DateTime.utc(2026, 8, 15);
      final hasil = mergeExpenses([expense('Tiket', at: at)], [expenseToJson(expense('Tiket', at: at))]);
      expect(hasil.length, 1);
    });

    test('id sama tapi isi beda, versi lokal yang dipakai', () {
      final at = DateTime.utc(2026, 8, 15);
      final hasil = mergeExpenses(
        [expense('Tiket Lokal', gbp: 50, at: at)],
        [expenseToJson(expense('Tiket Server', gbp: 10, at: at))],
      );
      expect(hasil.length, 1);
      expect(hasil.first.title, 'Tiket Lokal');
      expect(hasil.first.amountGbp, 50.0);
    });

    test('server kosong tidak mengubah apa pun', () {
      final lokal = [expense('Tiket')];
      expect(mergeExpenses(lokal, const []).length, 1);
    });

    test('lokal kosong mengambil semua dari server', () {
      final hasil = mergeExpenses(const [], [expenseToJson(expense('A')), expenseToJson(expense('B', at: DateTime.utc(2026, 8, 16)))]);
      expect(hasil.length, 2);
    });
  });

  group('merge prediksi', () {
    test('satu prediksi per matchId', () {
      final hasil = mergePredictions(
        [prediction(7001, 2, 1)],
        [predictionToJson(prediction(7001, 3, 0)), predictionToJson(prediction(7002, 1, 1))],
      );
      expect(hasil.length, 2);
    });

    test('matchId sama, versi lokal yang dipakai', () {
      final hasil = mergePredictions(
        [prediction(7001, 2, 1)],
        [predictionToJson(prediction(7001, 3, 0))],
      );
      expect(hasil.length, 1);
      expect(hasil.first.homeScore, 2);
      expect(hasil.first.awayScore, 1);
    });

    test('prediksi dari server masuk tanpa hilang', () {
      final hasil = mergePredictions(const [], [predictionToJson(prediction(7002, 0, 0))]);
      expect(hasil.length, 1);
      expect(hasil.first.matchId, 7002);
    });
  });

  group('SyncPayload', () {
    test('json memuat keempat koleksi', () {
      final p = SyncPayload(
        expenses: [expenseToJson(expense('A'))],
        chain: [
          {'index': 0, 'type': 'genesis'}
        ],
        predictions: [predictionToJson(prediction(1, 1, 1))],
        feedback: {'kesan': 'Bagus'},
      ).toJson();
      expect((p['expenses'] as List).length, 1);
      expect((p['chain'] as List).length, 1);
      expect((p['predictions'] as List).length, 1);
      expect((p['feedback'] as Map)['kesan'], 'Bagus');
    });

    test('feedback yang null tidak dikirim sebagai key', () {
      final p = const SyncPayload().toJson();
      expect(p.containsKey('feedback'), isFalse);
      expect(p['expenses'], isEmpty);
      expect(p['chain'], isEmpty);
      expect(p['predictions'], isEmpty);
    });

    test('tidak ada key trip di payload', () {
      expect(const SyncPayload().toJson().containsKey('trip'), isFalse);
    });
  });
}
