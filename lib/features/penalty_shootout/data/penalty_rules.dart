import 'dart:math' as math;

import '../../../core/utils/crypto_utils.dart';

/// Mini game Penalty Shootout.
///
/// Sesuai rubrik:
/// - arah tendangan     = kemiringan HP dari roll accelerometer
///                        (`atan2(x, z)`), bukan `gyroscope.z` yang hanya
///                        mengukur laju putar.
/// - kekuatan tendangan = puncak ayunan accelerometer di atas gravitasi
///
/// Parameter [tiltZ] pada [PenaltyRules.evaluate] menerima nilai roll tersebut
/// dalam radian; positif berarti HP condong ke kanan.
///
/// Logika di file ini murni dan tidak menyentuh sensor, jadi bisa diuji.
/// Sensor hanya dibaca di provider.
enum ShotOutcome { goal, savedByKeeper, tooWeak, wide }

class ShotResult {
  const ShotResult({
    required this.outcome,
    required this.quality,
    required this.accuracy,
    required this.power,
  });

  final ShotOutcome outcome;

  /// 0..1, gabungan akurasi arah dan kekuatan. Dipakai untuk skor.
  final double quality;
  final double accuracy;
  final double power;

  bool get isGoal => outcome == ShotOutcome.goal;
}

class PenaltyRules {
  const PenaltyRules({
    this.attempts = 5,
    this.aimTolerance = 0.20,
    this.minShake = 4.0,
    this.maxShake = 22.0,
    this.minPower = 0.15,
  });

  /// Jumlah tendangan per sesi (rubrik: 5).
  final int attempts;

  /// Toleransi kemiringan dalam radian. 0.20 rad sekitar 11,5 derajat.
  final double aimTolerance;

  /// Ayunan dianggap lemah di bawah nilai ini (m/s^2).
  final double minShake;

  /// Ayunan dianggap maksimum di nilai ini (m/s^2).
  final double maxShake;

  /// Di bawah power ini tendangan dianggap terlalu lemah oleh kiper.
  final double minPower;

  ShotResult evaluate({
    required double tiltZ,
    required double shake,
    required double keeperDive,
  }) {
    final tol = aimTolerance;

    // Di luar toleransi arah, bola melebar.
    if (tiltZ.abs() > tol) {
      return ShotResult(
        outcome: ShotOutcome.wide,
        quality: 0,
        accuracy: 0,
        power: power(shake),
      );
    }

    // Makin dekat ke tengah gawang, makin akurat.
    final accuracy = 1 - (tiltZ.abs() / tol);
    final p = power(shake);

    if (p < minPower) {
      return ShotResult(
        outcome: ShotOutcome.tooWeak,
        quality: 0,
        accuracy: accuracy,
        power: p,
      );
    }

    final quality = accuracy * 0.6 + p * 0.4;
    final outcome =
        keeperDive > quality ? ShotOutcome.savedByKeeper : ShotOutcome.goal;
    return ShotResult(
      outcome: outcome,
      quality: quality,
      accuracy: accuracy,
      power: p,
    );
  }

  /// Normalisasi kekuatan ayunan ke rentang 0..1.
  double power(double shake) {
    if (maxShake <= minShake) return 0;
    return ((shake - minShake) / (maxShake - minShake)).clamp(0.0, 1.0);
  }
}

const penaltyRules = PenaltyRules();

/// Nilai 0..1 untuk peluang keeper menangkap. Caller yang meng-seed RNG
/// supaya perilakunya bisa diuji.
double keeperDive(math.Random rnd) => rnd.nextDouble();

/// Skor akhir sesi: jumlah gol dikalikan rata-rata kualitas gol.
int sessionScore(List<ShotResult> results) {
  final goals = results.where((r) => r.isGoal).toList();
  if (goals.isEmpty) return 0;
  final avg = goals.fold<double>(0, (s, r) => s + r.quality) / goals.length;
  return (goals.length * avg * 100).round();
}

/// Hash hasil sesi untuk blok achievement, supaya skor tidak bisa diubah
/// diam-diam tanpa membuat rantai invalid.
String sessionHash({
  required int score,
  required int goals,
  required int attempts,
}) =>
    CryptoUtils.sha256Hash('penalty_shootout|$score|$goals|$attempts');

/// Tendangan acak untuk mode demo saat sensor tidak tersedia.
({double tiltZ, double shake}) demoShot(math.Random rnd) {
  // Condongkan gawang pada 60% tendangan, sisanya netral.
  final biased = rnd.nextDouble() < 0.6;
  final tilt = biased
      ? (rnd.nextDouble() * 2 - 1) * penaltyRules.aimTolerance * 0.9
      : 0.0;
  final shake = penaltyRules.minShake +
      rnd.nextDouble() * (penaltyRules.maxShake - penaltyRules.minShake) * 0.8;
  return (tiltZ: tilt, shake: shake);
}

/// Apakah HP cukup diam untuk memulai tendangan.
bool steadyEnough(double tiltZ, {double tolerance = 0.35}) => tiltZ.abs() <= tolerance;

/// Roll accelerometer -> sudut kemiringan kiri-kanan (rad).
///
/// HP datar (x = 0) menghasilkan 0; miring ke kanan menghasilkan nilai positif.
/// Dipakai provider sebagai sumber arah tendangan, dipisah agar bisa diuji.
double rollFromAccel(double x, double z) => math.atan2(x, z);

/// Magnitudo ayunan dari satu sampel accelerometer: jarak vektor terhadap
/// gravitasi (~9.81 m/s^2). Nilai mendekati 0 saat HP diam.
double shakeFromAccel(double x, double y, double z, {double gravity = 9.81}) {
  final magnitude = math.sqrt(x * x + y * y + z * z);
  return magnitude - gravity;
}

double degrees(double radians) => radians * 180 / math.pi;
