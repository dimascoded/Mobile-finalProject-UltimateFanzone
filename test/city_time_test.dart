import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/away_day/data/city_time.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';

PlClub _club(String key, String city, double lng) => PlClub(
      key: key,
      name: key,
      shortName: key,
      tla: key.toUpperCase(),
      city: city,
      stadium: '$key Stadium',
      lat: 0,
      lng: lng,
      color: 0xFF000000,
      aliases: const [],
    );

void main() {
  group('solarOffset', () {
    test('bujur 0 tidak menghasilkan offset', () {
      expect(solarOffset(0), Duration.zero);
    });

    test('15 derajat timur sama dengan satu jam', () {
      expect(solarOffset(15), const Duration(hours: 1));
    });

    test('-2.2 derajat sama dengan -528 detik', () {
      expect(solarOffset(-2.2).inSeconds, -528);
    });

    test('106.85 derajat sama dengan 25644 detik', () {
      expect(solarOffset(106.85).inSeconds, 25644);
    });
  });

  group('solarTime', () {
    test('menambahkan offset ke momen UTC', () {
      final utc = DateTime.utc(2026, 10, 15, 12);
      expect(solarTime(utc, 15), utc.add(const Duration(hours: 1)));
      expect(solarTime(utc, 0), utc);
    });
  });

  group('formatOffset', () {
    test('-528 detik menjadi "-8 mnt 48 dtk"', () {
      expect(formatOffset(const Duration(seconds: -528)), '-8 mnt 48 dtk');
    });

    test('25644 detik sama dengan +7 j 07 mnt 24 dtk', () {
      expect(
          formatOffset(const Duration(seconds: 25644)), '+7 j 07 mnt 24 dtk');
    });

    test('nol detik tanpa tanda', () {
      expect(formatOffset(Duration.zero), '0 dtk');
    });
  });

  group('cityLongitudes', () {
    test('merata-ratakan dua klub dari kota yang sama', () {
      final clubs = [
        _club('a', 'London', -0.2),
        _club('b', 'London', 0.2),
        _club('c', ' Leeds ', 1.5),
      ];
      final map = cityLongitudes(clubs);
      expect(map['London'], closeTo(0.0, 1e-9));
      expect(map['Leeds'], 1.5);
      expect(map.length, 2);
    });
  });

  test('daftar kota Indonesia tidak punya nama duplikat', () {
    final names = indonesianCities.map((c) => c.name).toList();
    expect(names.toSet().length, names.length);
    expect(indonesianCities, isNotEmpty);
  });
}
