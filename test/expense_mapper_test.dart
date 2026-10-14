import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/lens/data/expense_mapper.dart';

void main() {
  // Rates API basis IDR: rates['GBP'] = GBP per 1 Rupiah (dipakai membagi).
  const rates = {'GBP': 0.00005, 'USD': 0.00006};

  group('toExpenseAmounts', () {
    test('IDR diteruskan apa adanya tanpa butuh kurs', () {
      final r = toExpenseAmounts(
        amountForeign: 66000,
        currency: 'IDR',
        rates: null,
      );
      expect(r, isNotNull);
      expect(r!.amountForeign, 66000);
      expect(r.amountIdr, 66000);
      expect(r.amountGbp, 0);
    });

    test('GBP dengan kurs menghasilkan Rupiah dan padanan GBP', () {
      final r = toExpenseAmounts(
        amountForeign: 68,
        currency: 'GBP',
        rates: rates,
      );
      expect(r, isNotNull);
      expect(r!.amountForeign, 68);
      expect(r.amountIdr, closeTo(68 / 0.00005, 0.001));
      expect(r.amountGbp, closeTo((68 / 0.00005) * 0.00005, 0.001));
    });

    test('kurs hilang: null tanpa manual, terisi dengan manual > 0', () {
      expect(
        toExpenseAmounts(amountForeign: 10, currency: 'USD', rates: const {}),
        isNull,
      );
      final withManual = toExpenseAmounts(
        amountForeign: 10,
        currency: 'USD',
        rates: const {},
        manualIdr: 150000,
      );
      expect(withManual, isNotNull);
      expect(withManual!.amountIdr, 150000);
      expect(withManual.amountGbp, 0);
    });

    test('manual <= 0 tetap null saat kurs hilang', () {
      expect(
        toExpenseAmounts(
          amountForeign: 10,
          currency: 'EUR',
          rates: null,
          manualIdr: 0,
        ),
        isNull,
      );
    });

    test('nominal tidak positif menghasilkan null', () {
      expect(
        toExpenseAmounts(amountForeign: 0, currency: 'IDR', rates: rates),
        isNull,
      );
      expect(
        toExpenseAmounts(amountForeign: -5, currency: 'GBP', rates: rates),
        isNull,
      );
    });
  });
}
