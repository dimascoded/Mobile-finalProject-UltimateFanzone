import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/away_day/data/currency_convert.dart';

void main() {
  // Fixed rates: exchangerate-api.com v4 basis IDR
  // {IDR: 1, GBP: 0.000047, USD: 0.00006, EUR: 0.000055}
  final rates = <String, double>{
    'IDR': 1,
    'GBP': 0.000047,
    'USD': 0.00006,
    'EUR': 0.000055,
  };

  group('convertCurrency', () {
    test('same currency returns identity', () {
      expect(convertCurrency(100, 'IDR', 'IDR', rates), 100);
      expect(convertCurrency(100, 'GBP', 'GBP', rates), 100);
    });

    test('GBP -> USD via IDR', () {
      // GBP 1 = 1/0.000047 IDR; USD = IDR * 0.00006
      const gbp = 100.0;
      final idr = gbp / rates['GBP']!;
      final usd = idr * rates['USD']!;
      expect(convertCurrency(gbp, 'GBP', 'USD', rates), closeTo(usd, 1e-9));
    });

    test('IDR -> EUR', () {
      expect(convertCurrency(100000, 'IDR', 'EUR', rates),
          closeTo(100000 * rates['EUR']!, 1e-9));
    });

    test('missing rate returns null', () {
      expect(convertCurrency(100, 'GBP', 'USD', {'IDR': 1}), isNull);
      expect(convertCurrency(100, 'JPY', 'USD', rates), isNull);
    });
  });

  group('formatMoney', () {
    test('IDR formatting', () {
      expect(formatMoney(1234567, 'IDR'), 'Rp 1.234.567');
    });

    test('GBP formatting', () {
      expect(formatMoney(1234.5, 'GBP'), '\u00A31.234,50');
    });

    test('USD formatting', () {
      expect(formatMoney(1000, 'USD'), '\$1.000,00');
    });

    test('EUR formatting', () {
      expect(formatMoney(1000, 'EUR'), '\u20AC1.000,00');
    });
  });

  group('summarizeExpenses', () {
    final items = [
      AwayDayExpense(
        title: 'Tiket',
        amountGbp: 10,
        amountIdr: (10 / rates['GBP']!),
        category: AwayDayCategory.tiket,
        date: DateTime(2026, 10, 15),
        currencyCode: 'GBP',
        amountForeign: 10,
      ),
      AwayDayExpense(
        title: 'Makan',
        amountGbp: 5,
        amountIdr: (5 / rates['GBP']!),
        category: AwayDayCategory.makanan,
        date: DateTime(2026, 10, 16),
        currencyCode: 'GBP',
        amountForeign: 5,
      ),
    ];

    test('normal list', () {
      final sum = summarizeExpenses(items, 'IDR', rates);
      expect(sum.totalIdr, closeTo(items[0].amountIdr + items[1].amountIdr, 1));
      expect(sum.fallbackCount, 0);
      expect(sum.skippedCount, 0);
    });

    test('missing live rate for one expense triggers fallback', () {
      final missingRates = <String, double>{
        'IDR': 1,
        'USD': 0.00006,
        'EUR': 0.000055,
      }; // GBP missing
      final itemsWithOneMissing = [
        AwayDayExpense(
          title: 'Tiket USD',
          amountGbp: 0,
          amountIdr: (100 / rates['USD']!),
          category: AwayDayCategory.tiket,
          date: DateTime(2026, 10, 15),
          currencyCode: 'USD',
          amountForeign: 100,
        ),
        AwayDayExpense(
          title: 'Hotel',
          amountGbp: 0,
          amountIdr: 1000000,
          category: AwayDayCategory.hotel,
          date: DateTime(2026, 10, 17),
          currencyCode: 'GBP',
          amountForeign: 100, // live rate missing, but has amountIdr
        ),
      ];
      final sum = summarizeExpenses(itemsWithOneMissing, 'IDR', missingRates);
      expect(sum.fallbackCount, 1);
      expect(sum.skippedCount, 0);
      expect(
          sum.totalIdr, closeTo(itemsWithOneMissing[0].amountIdr + 1000000, 1));
    });

    test('no usable rate at all - skipped, excluded', () {
      final badRates = <String, double>{'IDR': 1}; // no others
      final itemBad = AwayDayExpense(
        title: 'Transport',
        amountGbp: 0,
        amountIdr: 0,
        category: AwayDayCategory.transport,
        date: DateTime(2026, 10, 18),
        currencyCode: 'GBP',
        amountForeign: 50,
      );
      final sum = summarizeExpenses([itemBad], 'IDR', badRates);
      expect(sum.skippedCount, 1);
      expect(sum.fallbackCount, 0);
      expect(sum.total, 0);
      expect(sum.totalIdr, 0);
    });
  });
}
