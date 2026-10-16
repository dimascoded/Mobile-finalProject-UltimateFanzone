import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';

void main() {
  // exchangerate-api.com v4 dengan basis IDR: rates['GBP'] = GBP per 1 Rupiah.
  // Nilai realistis ~1 GBP = Rp 19.000, jadi rates['GBP'] ~ 0.0000526.
  final rates = <String, double>{
    'GBP': 1 / 19000,
    'USD': 1 / 16000,
    'EUR': 1 / 17000,
  };

  group('konversi multi-mata-uang', () {
    test('USD dan EUR dikonversi ke Rupiah memakai basis IDR', () {
      expect(foreignToIdr(10, 'USD', rates), closeTo(160000, 1));
      expect(foreignToIdr(10, 'EUR', rates), closeTo(170000, 1));
    });

    test('Rupiah dapat dikonversi kembali ke USD dan EUR', () {
      expect(idrToForeign(160000, 'USD', rates), closeTo(10, 0.0001));
      expect(idrToForeign(170000, 'EUR', rates), closeTo(10, 0.0001));
    });

    test('IDR adalah konversi identitas dan kurs hilang menghasilkan null', () {
      expect(foreignToIdr(25000, 'IDR', null), 25000);
      expect(idrToForeign(25000, 'IDR', null), 25000);
      expect(foreignToIdr(10, 'EUR', {'USD': 1 / 16000}), isNull);
    });
  });

  group('gbpToIdr', () {
    test('membagi dengan kurs, bukan mengali', () {
      expect(gbpToIdr(100, rates), closeTo(1900000, 1));
    });

    test('nol pound menghasilkan nol', () {
      expect(gbpToIdr(0, rates), 0);
    });

    test('kurs null menghasilkan null', () {
      expect(gbpToIdr(100, null), isNull);
    });

    test('kurs tanpa GBP menghasilkan null', () {
      expect(gbpToIdr(100, {'USD': 0.1}), isNull);
    });

    test('kurs nol tidak menghasilkan divide by zero', () {
      expect(gbpToIdr(100, {'GBP': 0}), isNull);
    });
  });

  group('idrToGbp', () {
    test('mengali dengan kurs', () {
      expect(idrToGbp(19000, rates), closeTo(1.0, 0.0001));
    });

    test('kurs null menghasilkan null', () {
      expect(idrToGbp(19000, null), isNull);
    });
  });

  test('gbpToIdr dan idrToGbp adalah invers', () {
    const gbp = 42.5;
    final back = idrToGbp(gbpToIdr(gbp, rates)!, rates);
    expect(back, closeTo(gbp, 0.0001));
  });
}
