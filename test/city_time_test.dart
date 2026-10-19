import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/away_day/data/city_time.dart';

void main() {
  test('daftar kota Indonesia tidak punya nama duplikat', () {
    final names = indonesianCities.map((c) => c.name).toList();
    expect(names.toSet().length, names.length);
    expect(indonesianCities, isNotEmpty);
  });
}
