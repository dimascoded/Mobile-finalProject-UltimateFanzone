import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/kickoff_reminder_provider.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/data/penalty_rules.dart';
import 'package:ultimate_fanzone/features/sos_emergency/data/notification_service.dart';

void main() {
  group('N1: id notifikasi kickoff dan hasil tidak bentrok', () {
    test('satu laga punya dua id berbeda', () {
      for (final id in [1, 7, 12, 380, 2026]) {
        expect(NotificationService.kickoffId(id),
            isNot(NotificationService.resultId(id)));
      }
    });

    test('tidak ada tabrakan untuk rentang id liga', () {
      final kickoff = <int>{};
      final result = <int>{};
      for (final id in [1, 7, 12, 380, 2026]) {
        kickoff.add(NotificationService.kickoffId(id));
        result.add(NotificationService.resultId(id));
      }
      expect(kickoff.intersection(result), isEmpty);
    });

    test('kickoffId dan resultId unik untuk rentang id laga', () {
      final ids = <int>{};
      for (var id = 1; id <= 50; id++) {
        ids.add(NotificationService.kickoffId(id));
        ids.add(NotificationService.resultId(id));
      }
      expect(ids.length, 100);
    });

    test('id SOS tidak dipakai pengingat laga', () {
      final used = <int>{
        for (final id in [1, 7, 12]) ...[
          NotificationService.kickoffId(id),
          NotificationService.resultId(id),
        ],
      };
      expect(used, isNot(contains(NotificationService.sosId)));
    });
  });

  group('N1b: slot kickoff tidak bentrok dengan id lain', () {
    const matchIds = [1, 2, 537000];

    test('kickoffIdForSlot memberi tiga id berbeda per laga', () {
      for (final id in matchIds) {
        final slots = {
          for (var slot = 0; slot < NotificationService.kickoffSlotCount; slot++)
            NotificationService.kickoffIdForSlot(id, slot),
        };
        expect(slots.length, NotificationService.kickoffSlotCount);
      }
    });

    test('slot 0 identik dengan kickoffId lama', () {
      for (final id in matchIds) {
        expect(NotificationService.kickoffIdForSlot(id, 0),
            NotificationService.kickoffId(id));
      }
    });

    test('slot kickoff tidak pernah sama dengan resultId', () {
      for (final id in matchIds) {
        final result = NotificationService.resultId(id);
        for (var slot = 0; slot < NotificationService.kickoffSlotCount; slot++) {
          expect(NotificationService.kickoffIdForSlot(id, slot), isNot(result));
        }
      }
    });

    test('slot kickoff antar laga (1, 2, 537000) tidak saling menimpa', () {
      final used = <int>{};
      for (final id in matchIds) {
        for (var slot = 0; slot < NotificationService.kickoffSlotCount; slot++) {
          used.add(NotificationService.kickoffIdForSlot(id, slot));
        }
        used.add(NotificationService.resultId(id));
      }
      // 3 laga x (3 slot kickoff + 1 hasil) = 12 id unik.
      expect(used.length, matchIds.length * 4);
      expect(used, isNot(contains(NotificationService.sosId)));
    });

    test('seluruh slot + hasil unik untuk rentang id laga', () {
      final used = <int>{};
      for (var id = 1; id <= 50; id++) {
        for (var slot = 0; slot < NotificationService.kickoffSlotCount; slot++) {
          used.add(NotificationService.kickoffIdForSlot(id, slot));
        }
        used.add(NotificationService.resultId(id));
      }
      expect(used.length, 50 * 4);
    });
  });

  group('N3: hanya laga tim favorit, maksimal 10', () {
    const fav = PlClub(
      key: 'ars',
      name: 'Arsenal FC',
      shortName: 'Arsenal',
      tla: 'ARS',
      city: 'London',
      stadium: 'Emirates Stadium',
      lat: 51.5549,
      lng: -0.1084,
      color: 0xFFEF0107,
      aliases: ['arsenal'],
    );
    const other = PlClub(
      key: 'che',
      name: 'Chelsea FC',
      shortName: 'Chelsea',
      tla: 'CHE',
      city: 'London',
      stadium: 'Stamford Bridge',
      lat: 51.4817,
      lng: -0.1910,
      color: 0xFF034694,
      aliases: ['chelsea'],
    );

    const neutral = PlClub(
      key: 'liv',
      name: 'Liverpool FC',
      shortName: 'Liverpool',
      tla: 'LIV',
      city: 'Liverpool',
      stadium: 'Anfield',
      lat: 53.4308,
      lng: -2.9608,
      color: 0xFFC8102E,
      aliases: ['liverpool'],
    );

    FootballMatch match(int id, bool favInvolved, Duration inFuture) {
      // favInvolved == false -> kedua tim bukan tim favorit.
      final home = favInvolved ? fav : neutral;
      final away = favInvolved ? other : neutral;
      return FootballMatch(
        id: id,
        kickoffUtc: DateTime.now().toUtc().add(inFuture),
        status: 'TIMED',
        matchday: id,
        homeName: home.name,
        awayName: away.name,
        homeShort: home.shortName,
        awayShort: away.shortName,
        homeTla: home.tla,
        awayTla: away.tla,
      );
    }

    test('laga tanpa tim favorit dibuang', () {
      final data = [
        match(1, false, const Duration(days: 1)),
        match(2, false, const Duration(days: 2)),
      ];
      expect(reminderTargets(data, fav), isEmpty);
    });

    test('hanya laga yang memuat tim favorit', () {
      final data = [
        match(1, false, const Duration(days: 1)),
        match(2, true, const Duration(days: 2)),
        match(3, false, const Duration(days: 3)),
      ];
      final targets = reminderTargets(data, fav);
      expect(targets.map((m) => m.id), [2]);
    });

    test('dibatasi 10 laga terdekat', () {
      final data = [
        for (var i = 1; i <= 30; i++) match(i, true, Duration(days: i)),
      ];
      final targets = reminderTargets(data, fav);
      expect(targets.length, maxKickoffReminders);
      expect(targets.first.id, 1);
      expect(targets.last.id, 10);
    });

    test('tanpa tim favorit tidak ada pengingat sama sekali', () {
      final data = [match(1, true, const Duration(days: 1))];
      expect(reminderTargets(data, null), isEmpty);
    });

    test('laga yang sudah lewat tidak dijadwalkan', () {
      final data = [match(1, true, const Duration(hours: -1))];
      expect(reminderTargets(data, fav), isEmpty);
    });

    test('laga lewat dibuang sebelum batas kuota 10', () {
      // 5 laga lewat (paling awal) + 20 laga mendatang. Bila kuota diterapkan
      // sebelum menyaring, slot terpakai laga lewat dan sisanya cuma 5.
      final data = [
        for (var i = 1; i <= 5; i++) match(i, true, Duration(hours: -i)),
        for (var i = 6; i <= 25; i++) match(i, true, Duration(days: i - 5)),
      ];
      final targets = reminderTargets(data, fav);
      expect(targets.length, maxKickoffReminders);
      expect(
        targets.every((m) => m.kickoffUtc.isAfter(DateTime.now().toUtc())),
        isTrue,
      );
      expect(targets.first.id, 6);
      expect(targets.last.id, 15);
    });

    test('tanpa tim favorit kosong walau banyak laga mendatang', () {
      final data = [
        for (var i = 1; i <= 5; i++) match(i, true, Duration(days: i)),
      ];
      expect(reminderTargets(data, null), isEmpty);
    });
  });

  group('P1: arah dari roll accelerometer', () {
    test('HP datar menghasilkan roll 0', () {
      expect(rollFromAccel(0, 0, 9.81), closeTo(0, 1e-9));
    });

    test('miring ke kanan positif, ke kiri negatif', () {
      expect(rollFromAccel(4.9, 0, 8.5), greaterThan(0));
      expect(rollFromAccel(-4.9, 0, 8.5), lessThan(0));
    });

    test('roll menentukan kolom zona tendangan', () {
      final nearCenter = zoneFromAim(
        roll: rollFromAccel(1.0, 0, 9.8),
        pitchDelta: 0,
      );
      final farRight = zoneFromAim(
        roll: rollFromAccel(8.0, 0, 3.0),
        pitchDelta: 0,
      );
      expect(nearCenter, KickZone.bottomMid);
      expect(farRight, KickZone.bottomRight);
    });

    test('shake dari accelerometer mendeteksi ayunan, bukan gravitasi', () {
      // HP diam tegak: tidak ada ayunan.
      expect(shakeFromAccel(0, 0, 9.81), closeTo(0, 1e-9));
      // Ayunan ke samping: positif.
      expect(shakeFromAccel(6.0, 0, 9.81), greaterThan(0));
    });
  });

  group('P2: kekuatan ayunan tidak selalu nol', () {
    test('ayunan ringan di atas ambang minimum masuk band weak', () {
      // Ayunan samping modest: komponen x besar, gravitasi masih di z.
      final light = shakeFromAccel(14.0, 0, 9.81);
      expect(light, greaterThan(weakPowerThreshold));
      expect(bandFromShake(light), PowerBand.weak);
    });

    test('ayunan tidak peluruh: puncak kedua tetap dipakai', () {
      final peak = shakeFromAccel(18.0, 0, 9.81);
      // Setelah puncak, sampel kecil tidak boleh menurunkan nilai.
      final after = shakeFromAccel(9.81, 0, 9.81);
      expect(after, lessThan(peak));
      expect(max(peak, after), peak);
    });
  });
}
