import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';

void main() {
  const matchId = 7001;
  const home = 'Arsenal';
  const away = 'Chelsea';

  group('commit', () {
    test('commit deterministik untuk input yang sama', () {
      final a = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'abc');
      final b = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'abc');
      expect(a, b);
    });

    test('salt berbeda menghasilkan commit berbeda', () {
      final a = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'abc');
      final b = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'xyz');
      expect(a, isNot(b));
    });

    test('matchId berbeda menghasilkan commit berbeda', () {
      final a = Prediction.computeCommit(
          matchId: 1, home: home, away: away, salt: 'abc');
      final b = Prediction.computeCommit(
          matchId: 2, home: home, away: away, salt: 'abc');
      expect(a, isNot(b));
    });

    test('blok commit tidak membocorkan salt maupun skor', () {
      final commit = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'rahasia');
      final data = Prediction.commitData(
        matchId: matchId,
        home: home,
        away: away,
        commit: commit,
        at: DateTime.utc(2026, 8, 1),
      );
      expect(data.containsKey('salt'), isFalse);
      expect(data.containsKey('pred'), isFalse);
      expect(data['commit'], commit);
      // isi blok tidak boleh memuat string salt
      expect(data.values.join('|').contains('rahasia'), isFalse);
    });
  });

  group('reveal', () {
    test('salt yang benar validasi commit', () {
      final commit = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'abc');
      expect(
        Prediction.verify(
            matchId: matchId,
            home: home,
            away: away,
            salt: 'abc',
            expectedCommit: commit),
        isTrue,
      );
    });

    test('salt yang salah ditolak', () {
      final commit = Prediction.computeCommit(
          matchId: matchId, home: home, away: away, salt: 'abc');
      expect(
        Prediction.verify(
            matchId: matchId,
            home: home,
            away: away,
            salt: 'evil',
            expectedCommit: commit),
        isFalse,
      );
    });

    test('commit milik laga lain tidak bisa dipakai', () {
      final otherCommit = Prediction.computeCommit(
          matchId: 9999, home: home, away: away, salt: 'abc');
      expect(
        Prediction.verify(
            matchId: matchId,
            home: home,
            away: away,
            salt: 'abc',
            expectedCommit: otherCommit),
        isFalse,
      );
    });

    test('blok hasil memuat salt, tebakan, skor resmi, dan poin', () {
      final data = Prediction.resultData(
        matchId: matchId,
        salt: 'abc',
        predHome: 2,
        predAway: 1,
        realHome: 2,
        realAway: 1,
        points: 4,
      );
      expect(data['salt'], 'abc');
      expect(data['pred'], '2-1');
      expect(data['final'], '2-1');
      expect(data['points'], 4);
    });
  });

  group('scorePoints', () {
    test('tebak pas dapat 3 + bonus arah = 4', () {
      expect(
          scorePoints(predHome: 2, predAway: 1, realHome: 2, realAway: 1), 4);
    });

    test('tebak pas seri dapat 3 + bonus (arah seri juga benar)', () {
      expect(
          scorePoints(predHome: 1, predAway: 1, realHome: 1, realAway: 1), 4);
    });

    test('meleset 1 gol dengan arah benar dapat 2 + 1', () {
      // pred 2-1, real 2-0 -> diff 1, kedua-duanya home menang
      expect(
          scorePoints(predHome: 2, predAway: 1, realHome: 2, realAway: 0), 3);
    });

    test('meleset 1 gol tapi arah salah dapat 2 saja', () {
      // pred 1-1 (seri), real 1-0 (home menang) -> diff 1, arah beda
      expect(
          scorePoints(predHome: 1, predAway: 1, realHome: 1, realAway: 0), 2);
    });

    test('meleset 2 gol dengan arah benar dapat 1 + 1', () {
      // pred 2-1, real 1-0 -> diff 2, kedua-duanya home menang
      expect(
          scorePoints(predHome: 2, predAway: 1, realHome: 1, realAway: 0), 2);
    });

    test('meleset lebih dari 2 gol dan arah salah dapat 0', () {
      // pred 5-0, real 0-3 -> diff 8, arah berlawanan
      expect(
          scorePoints(predHome: 5, predAway: 0, realHome: 0, realAway: 3), 0);
    });

    test('tidak pernah negatif untuk semua kombinasi kecil', () {
      for (var h = 0; h <= 4; h++) {
        for (var a = 0; a <= 4; a++) {
          for (var rh = 0; rh <= 4; rh++) {
            for (var ra = 0; ra <= 4; ra++) {
              final p = scorePoints(
                  predHome: h, predAway: a, realHome: rh, realAway: ra);
              expect(p, greaterThanOrEqualTo(0));
              expect(p, lessThanOrEqualTo(4));
            }
          }
        }
      }
    });
  });

  test('salt acak cukup panjang untuk tahan tebak sambil komit', () {
    final rnd = Random(42);
    for (var i = 0; i < 50; i++) {
      final salt =
          List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
      expect(salt.length, 16);
    }
  });
}
