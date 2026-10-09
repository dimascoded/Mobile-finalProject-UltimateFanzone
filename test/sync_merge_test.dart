import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/away_day/data/away_day_repository.dart';
import 'package:smart_football_fan/features/prediction/data/prediction_repository.dart';
import 'package:smart_football_fan/features/sync/data/sync_models.dart';

AwayDayExpense expense(
  String title, {
  double gbp = 10,
  String currencyCode = 'GBP',
  double? amountForeign,
  DateTime? at,
}) =>
    AwayDayExpense(
      title: title,
      amountGbp: gbp,
      amountIdr: gbp * 20000,
      currencyCode: currencyCode,
      amountForeign: amountForeign ?? gbp,
      category: AwayDayCategory.tiket,
      date: at ?? DateTime.utc(2026, 8, 15, 14),
    );

Prediction prediction(int matchId, int home, int away, {DateTime? createdAt}) =>
    Prediction(
      matchId: matchId,
      homeScore: home,
      awayScore: away,
      salt: 'salt$matchId',
      commit: 'commit$matchId',
      createdAt: createdAt,
    );

void main() {
  group('payload expense', () {
    test('id expense_follows tanggal ISO', () {
      final at = DateTime.utc(2026, 8, 15, 14, 30);
      expect(
          expenseToJson(expense('Tiket', at: at))['id'], at.toIso8601String());
    });

    test('kirim kedua mata uang dan kategori', () {
      final j = expenseToJson(expense('Tiket', gbp: 45));
      expect(j['amountGbp'], 45.0);
      expect(j['amountIdr'], 900000.0);
      expect(j['currencyCode'], 'GBP');
      expect(j['amountForeign'], 45.0);
      expect(j['category'], 'tiket');
    });

    test('mata uang dan nominal asal USD/EUR tidak hilang di payload', () {
      final usd = expenseToJson(
        expense('Tiket', gbp: 40, currencyCode: 'USD', amountForeign: 25),
      );
      final eur = expenseToJson(
        expense('Hotel', gbp: 50, currencyCode: 'EUR', amountForeign: 30),
      );
      expect(usd['currencyCode'], 'USD');
      expect(usd['amountForeign'], 25);
      expect(eur['currencyCode'], 'EUR');
      expect(eur['amountForeign'], 30);
    });

    test('round trip json tidak mengubah data', () {
      final asli = expense('Hotel', gbp: 120);
      final kembali = expenseFromJson(expenseToJson(asli));
      expect(kembali.title, 'Hotel');
      expect(kembali.amountGbp, 120.0);
      expect(kembali.currencyCode, 'GBP');
      expect(kembali.amountForeign, 120.0);
      expect(kembali.category, AwayDayCategory.tiket);
      expect(kembali.id, asli.id);
    });

    test('record lama tanpa kolom mata uang tetap dianggap GBP', () {
      final legacy = AwayDayExpense.fromJson({
        'title': 'Tiket lama',
        'amountGbp': 25,
        'amountIdr': 500000,
        'category': 'tiket',
        'date': '2026-08-15T14:00:00Z',
      });
      expect(legacy.currencyCode, 'GBP');
      expect(legacy.amountForeign, 25);
    });

    test('kategori tidak dikenal jatuh ke lainnya', () {
      final j = expenseToJson(expense('X'))..['category'] = 'entah';
      expect(expenseFromJson(j).category, AwayDayCategory.lainnya);
    });
  });

  group('payload prediksi', () {
    test('S4: sebelum kickoff hanya matchId, commit, dan createdAt', () {
      final j = predictionCommitToJson(prediction(7001, 2, 1));
      expect(j.keys.toSet(), {'matchId', 'commit', 'createdAt'});
      expect(j['matchId'], 7001);
      expect(j['commit'], 'commit7001');
    });

    test('S4: skor dan salt tidak ikut terkirim sebelum kickoff', () {
      final j = predictionCommitToJson(prediction(7001, 2, 1));
      expect(j.containsKey('salt'), isFalse);
      expect(j.containsKey('homeScore'), isFalse);
      expect(j.containsKey('awayScore'), isFalse);
      // Teks gabungan tidak boleh memuat jejak salt.
      expect(j.values.join('|').contains('salt7001'), isFalse);
    });

    test('S4: bentuk penuh dipakai setelah blok result ditulis', () {
      final j = revealedPredictionToJson(prediction(7001, 2, 1));
      expect(j['salt'], 'salt7001');
      expect(j['homeScore'], 2);
      expect(j['awayScore'], 1);
    });

    test('round trip json tidak mengubah data', () {
      final kembali =
          predictionFromJson(revealedPredictionToJson(prediction(42, 0, 3)));
      expect(kembali.matchId, 42);
      expect(kembali.homeScore, 0);
      expect(kembali.awayScore, 3);
      expect(kembali.salt, 'salt42');
    });

    test('R2: item tanpa salt ditolak, bukan dipaksa jadi data salah', () {
      expect(
        () => Prediction.fromJson({'matchId': 1, 'commit': 'abc'}),
        throwsFormatException,
      );
    });

    test('R2: createdAt bertahan saat round trip', () {
      final asli =
          prediction(42, 1, 1, createdAt: DateTime.utc(2026, 8, 15, 14));
      final kembali = Prediction.fromJson(revealedPredictionToJson(asli));
      expect(kembali.createdAt, asli.createdAt);
    });
  });

  group('S4: bentuk payload dipilih dari rantai', () {
    Map<String, dynamic> resultBlock(int matchId) => {
          'index': 2,
          'type': Prediction.blockTypeResult,
          'data': {'match': matchId, 'salt': 'x', 'points': 3},
        };

    test('tanpa blok result hanya commit yang dikirim', () {
      final out = predictionsToSync([
        prediction(7001, 2, 1)
      ], const [
        {'index': 0, 'type': 'genesis', 'data': {}},
      ]);
      expect(out.single.keys.toSet(), {'matchId', 'commit', 'createdAt'});
    });

    test('ada blok result untuk laga itu, bentuk penuh yang dikirim', () {
      final out = predictionsToSync(
        [prediction(7001, 2, 1)],
        [resultBlock(7001)],
      );
      expect(out.single['salt'], 'salt7001');
      expect(out.single['homeScore'], 2);
      expect(out.single['awayScore'], 1);
    });

    test('blok result laga lain tidak membuka prediksi ini', () {
      final out = predictionsToSync(
        [prediction(7001, 2, 1)],
        [resultBlock(9999)],
      );
      expect(out.single.containsKey('salt'), isFalse);
    });

    test('blok commit saja tidak cukup untuk membuka salt', () {
      final out = predictionsToSync(
        [prediction(7001, 2, 1)],
        [
          {
            'index': 1,
            'type': Prediction.blockTypeCommit,
            'data': {'match': 7001, 'commit': 'commit7001'},
          },
        ],
      );
      expect(out.single.containsKey('salt'), isFalse);
    });

    test('campuran: hanya prediksi yang sudah selesai yang terbuka', () {
      final out = predictionsToSync(
        [prediction(7001, 2, 1), prediction(7002, 0, 0)],
        [resultBlock(7002)],
      );
      expect(out[0].containsKey('salt'), isFalse);
      expect(out[1]['salt'], 'salt7002');
    });

    test('blok tanpa data tidak membuat crash', () {
      final out = predictionsToSync(
        [prediction(7001, 1, 0)],
        [
          {'index': 3, 'type': Prediction.blockTypeResult},
        ],
      );
      expect(out.single.containsKey('salt'), isFalse);
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
      final hasil = mergeExpenses([expense('Tiket', at: at)],
          [expenseToJson(expense('Tiket', at: at))]);
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
      final hasil = mergeExpenses(const [], [
        expenseToJson(expense('A')),
        expenseToJson(expense('B', at: DateTime.utc(2026, 8, 16)))
      ]);
      expect(hasil.length, 2);
    });
  });

  group('merge prediksi', () {
    test('satu prediksi per matchId', () {
      final hasil = mergePredictions(
        [prediction(7001, 2, 1)],
        [
          revealedPredictionToJson(prediction(7001, 3, 0)),
          revealedPredictionToJson(prediction(7002, 1, 1))
        ],
      );
      expect(hasil.length, 2);
    });

    test('matchId sama, versi lokal yang dipakai', () {
      final hasil = mergePredictions(
        [prediction(7001, 2, 1)],
        [revealedPredictionToJson(prediction(7001, 3, 0))],
      );
      expect(hasil.length, 1);
      expect(hasil.first.homeScore, 2);
      expect(hasil.first.awayScore, 1);
    });

    test('prediksi dari server masuk tanpa hilang', () {
      final hasil = mergePredictions(
          const [], [revealedPredictionToJson(prediction(7002, 0, 0))]);
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
        predictions: [revealedPredictionToJson(prediction(1, 1, 1))],
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
