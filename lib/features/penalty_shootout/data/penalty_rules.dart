import 'dart:math' as math;

import '../../../core/utils/crypto_utils.dart';

/// Aturan adu penalti: murni Dart (tanpa I/O) supaya bisa diuji tanpa sensor.
///
/// Input berasal dari aksen sensor di `penalty_provider` (roll/pitch/goyangan),
/// dipetakan ke zona & kekuatan, lalu [resolveKick] memutuskan hasil. Lihat
/// `docs/feature-map.md` (bagian penalty_shootout).

/// Enam zona sasaran pada gawang (2 baris x 3 kolom).
enum KickZone {
  topLeft,
  topMid,
  topRight,
  bottomLeft,
  bottomMid,
  bottomRight;

  /// Kolom 0..2 (kiri/tengah/kanan).
  int get col => switch (this) {
        KickZone.topLeft || KickZone.bottomLeft => 0,
        KickZone.topMid || KickZone.bottomMid => 1,
        KickZone.topRight || KickZone.bottomRight => 2,
      };

  /// Baris 0 (atas) atau 1 (bawah).
  int get row => switch (this) {
        KickZone.topLeft || KickZone.topMid || KickZone.topRight => 0,
        KickZone.bottomLeft || KickZone.bottomMid || KickZone.bottomRight => 1,
      };
}

/// Kekuatan ayunan dari besarnya goyangan.
enum PowerBand { none, weak, sweet, tooHard }

/// Hasil satu tendangan.
enum ShotOutcome { goal, saved, overBar }

/// Ambang bawah goyangan untuk dianggap "ada tendangan".
const double weakPowerThreshold = 4;

/// Ambang kekuatan sedang (masih bisa jadi gol di sudut atas).
const double sweetPowerThreshold = 8;

/// Ambang di atas mana bola melambung ([ShotOutcome.overBar]).
const double tooHardPowerThreshold = 16;

/// Ambang minimum goyangan untuk memicu tendangan.
const double kickTriggerThreshold = 5;

/// Ambang roll untuk memilih kolom (kiri/kanan vs tengah).
const double aimColumnThreshold = 0.12;

/// Ambang pitch untuk memilih baris atas.
const double aimTopThreshold = 0.15;

/// Peta besar goyangan [shake] ke [PowerBand].
PowerBand bandFromShake(double shake) {
  if (shake < weakPowerThreshold) return PowerBand.none;
  if (shake < sweetPowerThreshold) return PowerBand.weak;
  if (shake <= tooHardPowerThreshold) return PowerBand.sweet;
  return PowerBand.tooHard;
}

/// Roll (kemiringan kiri/kanan) dari aksen accelerometer.
double rollFromAccel(double x, double y, double z) =>
    math.atan2(x, math.sqrt(y * y + z * z));

/// Pitch dasar dari aksen accelerometer.
double pitchFromAccel(double y, double z) => math.atan2(z, y);

/// Kekuatan hentakan: besar vektor dikurangi gravitasi (9.81).
double shakeFromAccel(double x, double y, double z) =>
    math.sqrt(x * x + y * y + z * z) - 9.81;

/// Peta arah bidik ([roll], [pitchDelta]) ke [KickZone].
KickZone zoneFromAim({required double roll, required double pitchDelta}) {
  final col = roll < -aimColumnThreshold
      ? 0
      : roll > aimColumnThreshold
          ? 2
          : 1;
  final row = pitchDelta > aimTopThreshold ? 0 : 1;
  return KickZone.values
      .singleWhere((zone) => zone.col == col && zone.row == row);
}

/// Pilih zona tebakan kiper: 40% meniru zona tersering di [history] (biar
/// terasa "belajar"), sisanya acak.
KickZone chooseKeeperZone(math.Random rnd, List<KickZone> history) {
  if (history.isNotEmpty && rnd.nextDouble() < 0.4) {
    final counts = <KickZone, int>{};
    for (final zone in history) {
      counts.update(zone, (count) => count + 1, ifAbsent: () => 1);
    }
    var mostFrequent = history.first;
    var highestCount = counts[mostFrequent]!;
    for (final zone in history.skip(1)) {
      final count = counts[zone]!;
      if (count > highestCount) {
        mostFrequent = zone;
        highestCount = count;
      }
    }
    return mostFrequent;
  }
  return KickZone.values[rnd.nextInt(KickZone.values.length)];
}

/// Hasil lengkap satu tendangan: zona, tebakan kiper, kekuatan, hasil, dan alasan.
class KickResult {
  const KickResult({
    required this.zone,
    required this.keeperZone,
    required this.band,
    required this.outcome,
    required this.reason,
  });

  final KickZone zone;
  final KickZone keeperZone;
  final PowerBand band;
  final ShotOutcome outcome;
  final String reason;
}

/// Putuskan hasil tendangan dari [zone], [band], dan [keeperZone].
///
/// Aturan: ayunan `tooHard` selalu melambung; tembakan `sweet` ke sudut atas
/// yang bertemu tebakan kiper tetap gol; selain itu zona yang sama = ditepis,
/// zona bersebelahan dengan ayunan lemah = ditepis, sisanya gol.
KickResult resolveKick({
  required KickZone zone,
  required PowerBand band,
  required KickZone keeperZone,
}) {
  late final ShotOutcome outcome;
  late final String reason;

  if (band == PowerBand.tooHard) {
    outcome = ShotOutcome.overBar;
    reason = 'Melambung, ayunan terlalu keras';
  } else if (zone == keeperZone &&
      ((zone == KickZone.topLeft || zone == KickZone.topRight) &&
          band == PowerBand.sweet)) {
    outcome = ShotOutcome.goal;
    reason =
        'GOL ${_zoneName(zone)}, melewati tebakan kiper ${_zoneName(keeperZone)}';
  } else if (zone == keeperZone) {
    outcome = ShotOutcome.saved;
    reason = 'Ditepis, kiper menebak ${_zoneName(keeperZone)}';
  } else if (_areAdjacent(zone, keeperZone) &&
      (band == PowerBand.none || band == PowerBand.weak)) {
    outcome = ShotOutcome.saved;
    reason =
        'Ditepis, kiper menebak ${_zoneName(keeperZone)} dekat ${_zoneName(zone)}';
  } else {
    outcome = ShotOutcome.goal;
    reason = 'GOL ${_zoneName(zone)}, kiper menebak ${_zoneName(keeperZone)}';
  }

  return KickResult(
    zone: zone,
    keeperZone: keeperZone,
    band: band,
    outcome: outcome,
    reason: reason,
  );
}

/// True bila [first] dan [second] bersebelahan (satu langkah horizontal/vertikal).
bool _areAdjacent(KickZone first, KickZone second) =>
    (first.row == second.row && (first.col - second.col).abs() == 1) ||
    (first.col == second.col && (first.row - second.row).abs() == 1);

String _zoneName(KickZone zone) => switch (zone) {
      KickZone.topLeft => 'kiri atas',
      KickZone.topMid => 'tengah atas',
      KickZone.topRight => 'kanan atas',
      KickZone.bottomLeft => 'kiri bawah',
      KickZone.bottomMid => 'tengah bawah',
      KickZone.bottomRight => 'kanan bawah',
    };

/// Aturan tetap adu penalti.
class PenaltyRules {
  const PenaltyRules();

  /// Jumlah tendangan reguler per sesi.
  static const int attempts = 5;
}

/// Instance aturan default.
const penaltyRules = PenaltyRules();

/// Skor sesi: 100 per gol, +50 sudut atas dengan ayunan `sweet`, +50 untuk
/// gol setelah [PenaltyRules.attempts] (sudden death).
int sessionScore(List<KickResult> results) {
  var score = 0;
  for (var index = 0; index < results.length; index++) {
    final result = results[index];
    if (result.outcome != ShotOutcome.goal) continue;
    score += 100;
    final topCorner =
        result.zone == KickZone.topLeft || result.zone == KickZone.topRight;
    if (topCorner && result.band == PowerBand.sweet) score += 50;
    if (index >= PenaltyRules.attempts) score += 50;
  }
  return score;
}

/// True bila sesi masuk sudden death: semua [attempts] tendangan pertama gol.
bool inSuddenDeath(List<KickResult> results, int attempts) {
  if (results.length < attempts) return false;
  return results.every((result) => result.outcome == ShotOutcome.goal);
}

/// Hash ringkas sesi permainan untuk blok rantai pencapaian.
String sessionHash({
  required int score,
  required int goals,
  required int attempts,
}) =>
    CryptoUtils.sha256Hash('penalty_shootout|$score|$goals|$attempts');

/// Tendangan tiruan acak (mode demo tanpa sensor).
({double roll, double pitchDelta, double shake}) demoShot(math.Random rnd) => (
      roll: rnd.nextDouble() * 0.8 - 0.4,
      pitchDelta: rnd.nextDouble() * 0.6 - 0.3,
      shake: rnd.nextDouble() * 20,
    );
