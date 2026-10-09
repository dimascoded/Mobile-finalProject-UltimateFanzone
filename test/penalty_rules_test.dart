import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/penalty_shootout/data/penalty_rules.dart';

void main() {
  group('zoneFromAim', () {
    test('memetakan semua enam zona', () {
      expect(
        zoneFromAim(roll: -0.2, pitchDelta: 0.2),
        KickZone.topLeft,
      );
      expect(
        zoneFromAim(roll: 0, pitchDelta: 0.2),
        KickZone.topMid,
      );
      expect(
        zoneFromAim(roll: 0.2, pitchDelta: 0.2),
        KickZone.topRight,
      );
      expect(
        zoneFromAim(roll: -0.2, pitchDelta: 0),
        KickZone.bottomLeft,
      );
      expect(
        zoneFromAim(roll: 0, pitchDelta: 0),
        KickZone.bottomMid,
      );
      expect(
        zoneFromAim(roll: 0.2, pitchDelta: 0),
        KickZone.bottomRight,
      );
    });

    test('nilai tepat di ambang roll tetap masuk kolom tengah', () {
      expect(zoneFromAim(roll: -aimColumnThreshold, pitchDelta: 0),
          KickZone.bottomMid);
      expect(zoneFromAim(roll: aimColumnThreshold, pitchDelta: 0),
          KickZone.bottomMid);
    });

    test('nilai tepat di ambang pitch masuk baris bawah', () {
      expect(zoneFromAim(roll: 0, pitchDelta: aimTopThreshold),
          KickZone.bottomMid);
    });
  });

  group('bandFromShake', () {
    test('mengikuti batas bawah, batas sweet, dan batas terlalu keras', () {
      expect(bandFromShake(weakPowerThreshold - 0.001), PowerBand.none);
      expect(bandFromShake(weakPowerThreshold), PowerBand.weak);
      expect(bandFromShake(sweetPowerThreshold - 0.001), PowerBand.weak);
      expect(bandFromShake(sweetPowerThreshold), PowerBand.sweet);
      expect(bandFromShake(tooHardPowerThreshold), PowerBand.sweet);
      expect(bandFromShake(tooHardPowerThreshold + 0.001), PowerBand.tooHard);
    });
  });

  group('resolveKick', () {
    test('tooHard melambung sebelum aturan zona diperiksa', () {
      final result = resolveKick(
        zone: KickZone.bottomMid,
        keeperZone: KickZone.bottomMid,
        band: PowerBand.tooHard,
      );
      expect(result.outcome, ShotOutcome.overBar);
      expect(result.reason, 'Melambung, ayunan terlalu keras');
    });

    test('tebakan zona yang sama menyelamatkan tendangan biasa', () {
      final result = resolveKick(
        zone: KickZone.bottomLeft,
        keeperZone: KickZone.bottomLeft,
        band: PowerBand.sweet,
      );
      expect(result.outcome, ShotOutcome.saved);
      expect(result.reason, contains('kiper menebak kiri bawah'));
    });

    test('sweet di sudut atas menembus tebakan keeper pada zona sama', () {
      for (final corner in [KickZone.topLeft, KickZone.topRight]) {
        final result = resolveKick(
          zone: corner,
          keeperZone: corner,
          band: PowerBand.sweet,
        );
        expect(result.outcome, ShotOutcome.goal);
        expect(result.reason, contains('GOL'));
      }
    });

    test('keeper bersebelahan menyelamatkan band none atau weak', () {
      for (final band in [PowerBand.none, PowerBand.weak]) {
        final result = resolveKick(
          zone: KickZone.bottomMid,
          keeperZone: KickZone.bottomLeft,
          band: band,
        );
        expect(result.outcome, ShotOutcome.saved);
        expect(result.reason, contains('kiri bawah'));
        expect(result.reason, contains('tengah bawah'));
      }
    });

    test('keeper bersebelahan tidak menyelamatkan tendangan sweet', () {
      final result = resolveKick(
        zone: KickZone.bottomMid,
        keeperZone: KickZone.bottomLeft,
        band: PowerBand.sweet,
      );
      expect(result.outcome, ShotOutcome.goal);
      expect(result.reason, contains('tengah bawah'));
      expect(result.reason, contains('kiri bawah'));
    });

    test('zona tak bersebelahan menjadi gol dan alasan menyebut kedua zona',
        () {
      final result = resolveKick(
        zone: KickZone.topRight,
        keeperZone: KickZone.bottomLeft,
        band: PowerBand.weak,
      );
      expect(result.outcome, ShotOutcome.goal);
      expect(result.reason, contains('kanan atas'));
      expect(result.reason, contains('kiri bawah'));
    });
  });

  group('chooseKeeperZone', () {
    test('Random dengan seed sama menghasilkan urutan yang sama', () {
      final history = [
        KickZone.topLeft,
        KickZone.bottomRight,
        KickZone.topLeft,
        KickZone.bottomMid,
      ];
      final firstRandom = Random(1);
      final firstSequential = List.generate(
        30,
        (_) => chooseKeeperZone(firstRandom, history),
      );
      final secondRandom = Random(1);
      final second = List.generate(
        30,
        (_) => chooseKeeperZone(secondRandom, history),
      );
      expect(firstSequential, second);
    });

    test('menggunakan zona paling sering saat cabang riwayat dipilih', () {
      final history = List<KickZone>.filled(8, KickZone.topRight);
      final rnd = Random(1);
      final selected =
          List.generate(100, (_) => chooseKeeperZone(rnd, history));
      expect(selected, contains(KickZone.topRight));
      expect(selected.where((zone) => zone == KickZone.topRight).length,
          greaterThan(20));
    });

    test('riwayat kosong memilih zona secara merata', () {
      final rnd = Random(1);
      final counts = {for (final zone in KickZone.values) zone: 0};
      for (var i = 0; i < 6000; i++) {
        counts.update(
          chooseKeeperZone(rnd, const []),
          (count) => count + 1,
        );
      }
      for (final count in counts.values) {
        expect(count, inInclusiveRange(850, 1150));
      }
    });
  });

  group('accelerometer helpers', () {
    test('roll mendekati nol saat HP datar dan tegak', () {
      expect(rollFromAccel(0, 0, 9.81), closeTo(0, 1e-10));
      expect(rollFromAccel(0, 9.81, 0), closeTo(0, 1e-10));
    });

    test('roll positif ketika x positif', () {
      expect(rollFromAccel(1, 0, 9.81), greaterThan(0));
    });

    test('pitch dan shake memakai komponen akselerometer', () {
      expect(pitchFromAccel(9.81, 0), closeTo(0, 1e-10));
      expect(pitchFromAccel(0, 9.81), closeTo(pi / 2, 1e-10));
      expect(shakeFromAccel(0, 0, 9.81), closeTo(0, 1e-10));
    });
  });

  group('sessionScore', () {
    test('seratus poin per gol dan bonus sudut atas sweet', () {
      final results = [
        resolveKick(
          zone: KickZone.bottomMid,
          keeperZone: KickZone.topLeft,
          band: PowerBand.weak,
        ),
        resolveKick(
          zone: KickZone.topRight,
          keeperZone: KickZone.bottomLeft,
          band: PowerBand.sweet,
        ),
      ];
      expect(sessionScore(results), 250);
    });

    test('gol sudden death mendapat tambahan 50 poin', () {
      final results = List.generate(
        PenaltyRules.attempts + 1,
        (index) => resolveKick(
          zone: index == PenaltyRules.attempts
              ? KickZone.bottomMid
              : KickZone.topMid,
          keeperZone: KickZone.bottomRight,
          band: PowerBand.sweet,
        ),
      );
      expect(sessionScore(results), 650);
    });

    test('saved dan overBar tidak memberi poin', () {
      final results = [
        resolveKick(
          zone: KickZone.bottomLeft,
          keeperZone: KickZone.bottomLeft,
          band: PowerBand.weak,
        ),
        resolveKick(
          zone: KickZone.topRight,
          keeperZone: KickZone.bottomLeft,
          band: PowerBand.tooHard,
        ),
      ];
      expect(sessionScore(results), 0);
    });
  });

  group('inSuddenDeath', () {
    KickResult goal() => resolveKick(
          zone: KickZone.bottomMid,
          keeperZone: KickZone.topLeft,
          band: PowerBand.sweet,
        );

    KickResult saved() => resolveKick(
          zone: KickZone.bottomMid,
          keeperZone: KickZone.bottomMid,
          band: PowerBand.weak,
        );

    test('belum cukup attempts bukan sudden death', () {
      expect(inSuddenDeath(List.generate(4, (_) => goal()), 5), isFalse);
    });

    test('semua gol setelah attempts berarti sudden death berlanjut', () {
      expect(inSuddenDeath(List.generate(7, (_) => goal()), 5), isTrue);
    });

    test('sudden death berakhir pada non-gol di attempts awal atau tambahan',
        () {
      expect(
          inSuddenDeath([goal(), goal(), saved(), goal(), goal()], 5), isFalse);
      expect(inSuddenDeath([...List.generate(5, (_) => goal()), saved()], 5),
          isFalse);
    });
  });

  group('demoShot', () {
    test('Random dengan seed sama menghasilkan tendangan demo sama', () {
      expect(demoShot(Random(9)), demoShot(Random(9)));
    });

    test('menghasilkan nilai plausibel', () {
      final rnd = Random(4);
      for (var i = 0; i < 100; i++) {
        final shot = demoShot(rnd);
        expect(shot.roll, inInclusiveRange(-0.4, 0.4));
        expect(shot.pitchDelta, inInclusiveRange(-0.3, 0.3));
        expect(shot.shake, inInclusiveRange(0, 20));
      }
    });
  });

  group('sessionHash', () {
    test('tetap deterministik dan berbentuk SHA-256 hex', () {
      final first = sessionHash(score: 300, goals: 4, attempts: 5);
      expect(sessionHash(score: 300, goals: 4, attempts: 5), first);
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(sessionHash(score: 301, goals: 4, attempts: 5), isNot(first));
    });
  });

  test('jumlah attempts tetap lima', () {
    expect(PenaltyRules.attempts, 5);
  });
}
