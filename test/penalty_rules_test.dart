import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:premiere_league_fan_assistant/features/penalty_shootout/data/penalty_rules.dart';

void main() {
  const r = penaltyRules;

  group('evaluate: arah', () {
    test('di luar toleransi melebar', () {
      final s = r.evaluate(tiltZ: 0.5, shake: 20, keeperDive: 0);
      expect(s.outcome, ShotOutcome.wide);
      expect(s.accuracy, 0);
      expect(s.quality, 0);
    });

    test('toleransi tepat accepted', () {
      final s = r.evaluate(tiltZ: r.aimTolerance, shake: 20, keeperDive: 0);
      expect(s.outcome, isNot(ShotOutcome.wide));
    });

    test('netral dan kuat selalu gol', () {
      final s = r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 0.99);
      expect(s.outcome, ShotOutcome.goal);
      expect(s.accuracy, 1.0);
      expect(s.power, 1.0);
    });

    test('accuracy maksimum di tengah gawang', () {
      expect(r.evaluate(tiltZ: 0, shake: 10, keeperDive: 0).accuracy, 1.0);
    });

    test('accuracy menurun seiring jauh dari tengah', () {
      final near = r.evaluate(tiltZ: 0.02, shake: 10, keeperDive: 0).accuracy;
      final far = r.evaluate(tiltZ: 0.18, shake: 10, keeperDive: 0).accuracy;
      expect(near, greaterThan(far));
      expect(far, greaterThan(0));
    });
  });

  group('evaluate: kekuatan', () {
    test('ayunan di bawah minShake berarti power 0', () {
      expect(r.power(0), 0);
      expect(r.power(r.minShake), 0);
    });

    test('ayunan di atas maxShake berarti power 1', () {
      expect(r.power(r.maxShake), 1);
      expect(r.power(999), 1);
    });

    test('power interpolasi linear', () {
      final mid = (r.minShake + r.maxShake) / 2;
      expect(r.power(mid), closeTo(0.5, 0.001));
    });

    test('terlalu lemah ditolak kiper', () {
      final s = r.evaluate(tiltZ: 0, shake: r.minShake + 0.1, keeperDive: 0);
      expect(s.outcome, ShotOutcome.tooWeak);
      expect(s.quality, 0);
    });

    test('power selalu dalam 0..1', () {
      for (final v in <double>[-50, 0, 4, 10, 22, 100]) {
        final p = r.power(v);
        expect(p, inInclusiveRange(0, 1));
      }
    });
  });

  group('evaluate: kiper', () {
    test('dive kiper yang lebih besar dari quality berarti tertahan', () {
      // shake 8 -> power 0.22 (cukup), tilt 0.19 -> quality rendah, jadi tertahan kiper.
      final s = r.evaluate(tiltZ: 0.19, shake: 8, keeperDive: 1.0);
      expect(s.outcome, ShotOutcome.savedByKeeper);
    });

    test('kualitas tinggi menembus kiper', () {
      final s = r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 0);
      expect(s.outcome, ShotOutcome.goal);
    });

    test('keeperDive tepat di batas menghasilkan gol', () {
      // quality = accuracy*0.6 + power*0.4; ambang strict '>' jadi sama = gol
      final s = r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 1.0);
      expect(s.quality, 1.0);
      expect(s.outcome, isNot(ShotOutcome.savedByKeeper));
    });
  });

  group('quality', () {
    test('selalu dalam 0..1', () {
      for (var t = -0.25; t <= 0.25; t += 0.01) {
        for (final sh in [r.minShake, 10.0, r.maxShake]) {
          final s = r.evaluate(tiltZ: t, shake: sh, keeperDive: 0);
          expect(s.quality, inInclusiveRange(0, 1));
        }
      }
    });

    test('gol selalu punya quality lebih dari 0', () {
      for (var t = -0.19; t <= 0.19; t += 0.01) {
        final s = r.evaluate(tiltZ: t, shake: r.maxShake, keeperDive: 0);
        if (s.isGoal) expect(s.quality, greaterThan(0));
      }
    });
  });

  group('sessionScore', () {
    test('nol gol berarti skor 0', () {
      final results = [
        r.evaluate(tiltZ: 0.5, shake: 20, keeperDive: 0),
        r.evaluate(tiltZ: 0.5, shake: 20, keeperDive: 0),
      ];
      expect(sessionScore(results), 0);
    });

    test('satu gol sempurna ber skor 100', () {
      final results = [r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 0)];
      expect(sessionScore(results), 100);
    });

    test('lima gol sempurna ber skor 500', () {
      final results = List.generate(
        r.attempts,
        (_) => r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 0),
      );
      expect(sessionScore(results), 500);
    });

    test('gol buruk menurunkan skor', () {
      final good = [r.evaluate(tiltZ: 0, shake: r.maxShake, keeperDive: 0)];
      final poor = [r.evaluate(tiltZ: 0.19, shake: 8, keeperDive: 0)];
      expect(sessionScore(poor), lessThan(sessionScore(good)));
    });

    test('skor tidak negatif dan tidak melebihi 100 per gol', () {
      final rnd = Random(7);
      for (var i = 0; i < 200; i++) {
        final results = <ShotResult>[];
        for (var k = 0; k < 5; k++) {
          final sh = demoShot(rnd);
          results.add(r.evaluate(
            tiltZ: sh.tiltZ,
            shake: sh.shake,
            keeperDive: keeperDive(rnd),
          ));
        }
        final s = sessionScore(results);
        expect(s, greaterThanOrEqualTo(0));
        expect(s, lessThanOrEqualTo(100 * results.where((e) => e.isGoal).length));
      }
    });
  });

  group('demoShot & seed', () {
    test('Random dengan seed sama menghasilkan hasil sama', () {
      final a = demoShot(Random(123));
      final b = demoShot(Random(123));
      expect(a.tiltZ, b.tiltZ);
      expect(a.shake, b.shake);
    });

    test('demoShot selalu di dalam toleransi arah', () {
      final rnd = Random(9);
      for (var i = 0; i < 500; i++) {
        final s = demoShot(rnd);
        expect(s.tiltZ.abs(), lessThanOrEqualTo(r.aimTolerance));
        expect(s.shake, greaterThanOrEqualTo(r.minShake));
        expect(s.shake, lessThanOrEqualTo(r.maxShake));
      }
    });
  });

  group('sessionHash', () {
    test('deterministik untuk input sama', () {
      final a = sessionHash(score: 300, goals: 4, attempts: 5);
      final b = sessionHash(score: 300, goals: 4, attempts: 5);
      expect(a, b);
    });

    test('skor berbeda menghasilkan hash berbeda', () {
      expect(
        sessionHash(score: 300, goals: 4, attempts: 5),
        isNot(sessionHash(score: 301, goals: 4, attempts: 5)),
      );
    });

    test('hash panjang 64 hex (sha256)', () {
      final h = sessionHash(score: 1, goals: 1, attempts: 5);
      expect(h.length, 64);
      expect(h, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('steadyEnough & degrees', () {
    test('steadyEnough menolak kemiringan besar', () {
      expect(steadyEnough(0.1), isTrue);
      expect(steadyEnough(0.9), isFalse);
    });

    test('degrees mengonversi radian ke derajat', () {
      expect(degrees(0), 0);
      expect(degrees(3.14159265358979 / 2), closeTo(90, 0.0001));
    });
  });

  test('aturan default sesuai rubrik: 5 tendangan', () {
    expect(r.attempts, 5);
  });
}
