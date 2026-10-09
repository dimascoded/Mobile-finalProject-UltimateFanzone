import 'dart:math';

import '../../penalty_shootout/data/penalty_rules.dart';

const int initialReflexTimeLimitMs = 1200;
const int reflexTimeStepMs = 100;
const int savesPerReflexLevel = 5;
const int minimumReflexTimeLimitMs = 500;
const int reflexLives = 3;

int levelForSaves(int saves) =>
    (saves < 0 ? 0 : saves) ~/ savesPerReflexLevel + 1;

int timeLimitForLevel(int level) {
  final safeLevel = max(1, level);
  final limit = initialReflexTimeLimitMs - (safeLevel - 1) * reflexTimeStepMs;
  return max(minimumReflexTimeLimitMs, limit);
}

int scoreForSave(int combo) => 10 * (1 + max(0, combo) ~/ 5);

int livesAfterMiss(int lives) => max(0, lives - 1);

int comboAfterSave(int combo) => max(0, combo) + 1;

int comboAfterMiss(int combo) => 0;

KickZone pickZone(Random rnd, KickZone? previous) {
  final choices =
      KickZone.values.where((zone) => zone != previous).toList(growable: false);
  return choices[rnd.nextInt(choices.length)];
}
