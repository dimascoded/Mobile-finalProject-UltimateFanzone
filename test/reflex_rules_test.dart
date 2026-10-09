import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/gamification/data/reflex_rules.dart';
import 'package:smart_football_fan/features/penalty_shootout/data/penalty_rules.dart';

void main() {
  group('timeLimitForLevel', () {
    test('starts at 1200 ms and decreases once per level', () {
      expect(timeLimitForLevel(1), 1200);
      expect(timeLimitForLevel(2), 1100);
      expect(timeLimitForLevel(5), 800);
    });

    test('never falls below 500 ms', () {
      expect(timeLimitForLevel(8), 500);
      expect(timeLimitForLevel(30), 500);
    });
  });

  group('levelForSaves', () {
    test('advances every five saves', () {
      expect(levelForSaves(0), 1);
      expect(levelForSaves(4), 1);
      expect(levelForSaves(5), 2);
      expect(levelForSaves(9), 2);
      expect(levelForSaves(10), 3);
    });
  });

  group('scoreForSave', () {
    test('awards combo-scaled points', () {
      expect(scoreForSave(0), 10);
      expect(scoreForSave(4), 10);
      expect(scoreForSave(5), 20);
      expect(scoreForSave(10), 30);
    });
  });

  group('life and combo transitions', () {
    test('miss loses one life without going negative', () {
      expect(livesAfterMiss(3), 2);
      expect(livesAfterMiss(1), 0);
      expect(livesAfterMiss(0), 0);
    });

    test('save increments combo and miss resets it', () {
      expect(comboAfterSave(0), 1);
      expect(comboAfterSave(4), 5);
      expect(comboAfterMiss(7), 0);
    });
  });

  test('pickZone never repeats the previous zone', () {
    final rnd = Random(42);
    var previous = KickZone.bottomMid;
    for (var i = 0; i < 500; i++) {
      final next = pickZone(rnd, previous);
      expect(next, isNot(previous));
      previous = next;
    }
  });
}
