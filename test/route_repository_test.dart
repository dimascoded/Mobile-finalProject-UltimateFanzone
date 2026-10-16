import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/stadium_pointer/data/route_repository.dart';

void main() {
  group('parseOsrmRoute', () {
    test('respons OSRM valid: balik [lng,lat] -> LatLng, km dan menit', () {
      final json = <String, dynamic>{
        'code': 'Ok',
        'routes': [
          {
            'distance': 12345.6, // meter
            'duration': 987.6, // detik
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [106.8456, -6.2088],
                [106.8252, -6.2215],
                [106.8080, -6.2260],
              ],
            },
          },
        ],
      };

      final result = parseOsrmRoute(json);

      expect(result, isNotNull);
      expect(result!.points, hasLength(3));
      // Urutan koordinat GeoJSON [lng, lat] harus dibalik ke LatLng(lat, lng).
      expect(result.points[0].latitude, closeTo(-6.2088, 1e-9));
      expect(result.points[0].longitude, closeTo(106.8456, 1e-9));
      expect(result.points[1].latitude, closeTo(-6.2215, 1e-9));
      expect(result.points[1].longitude, closeTo(106.8252, 1e-9));
      expect(result.points[2].latitude, closeTo(-6.2260, 1e-9));
      expect(result.points[2].longitude, closeTo(106.8080, 1e-9));
      expect(result.distanceKm, closeTo(12.3456, 1e-9));
      expect(result.durationMin, closeTo(987.6 / 60, 1e-9));
    });

    test('code NoRoute dengan routes kosong -> null', () {
      final json = <String, dynamic>{
        'code': 'NoRoute',
        'routes': <dynamic>[],
      };

      expect(parseOsrmRoute(json), isNull);
    });

    test('JSON rusak -> null tanpa exception', () {
      expect(parseOsrmRoute(<String, dynamic>{}), isNull);
      expect(
        parseOsrmRoute(<String, dynamic>{'code': 'Ok', 'routes': 'bukan-list'}),
        isNull,
      );
      expect(
        parseOsrmRoute(<String, dynamic>{
          'code': 'Ok',
          'routes': [
            {'geometry': null},
          ],
        }),
        isNull,
      );
      expect(
        parseOsrmRoute(<String, dynamic>{
          'code': 'Ok',
          'routes': [
            {
              'distance': 1000,
              'duration': 60,
              'geometry': {
                'coordinates': [
                  [106.8],
                ],
              },
            },
          ],
        }),
        isNull,
      );
      expect(
        parseOsrmRoute(<String, dynamic>{
          'code': 'Ok',
          'routes': [
            {
              'distance': 'seratus',
              'duration': 60,
              'geometry': {
                'coordinates': [
                  [106.8, -6.2],
                ],
              },
            },
          ],
        }),
        isNull,
      );
    });
  });
}
