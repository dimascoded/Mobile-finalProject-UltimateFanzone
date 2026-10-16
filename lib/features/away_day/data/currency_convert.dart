import 'away_day_repository.dart';

/// Informasi mata uang yang didukung.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.decimals,
    required this.name,
  });

  final String code;
  final String symbol;
  final int decimals;
  final String name;
}

/// Daftar mata uang yang didukung untuk Away Day.
const supportedCurrencies = <String, CurrencyInfo>{
  'GBP': CurrencyInfo(
      code: 'GBP', symbol: '\u00A3', decimals: 2, name: 'Poundsterling'),
  'USD': CurrencyInfo(code: 'USD', symbol: '\$', decimals: 2, name: 'Dolar AS'),
  'EUR': CurrencyInfo(code: 'EUR', symbol: '\u20AC', decimals: 2, name: 'Euro'),
  'IDR': CurrencyInfo(code: 'IDR', symbol: 'Rp', decimals: 0, name: 'Rupiah'),
};

double? _foreignToIdrInline(
  double amount,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return amount;
  final rate = rates?[currency];
  if (rate == null || rate == 0) return null;
  return amount / rate;
}

double? _idrToForeignInline(
  double idr,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return idr;
  final rate = rates?[currency];
  if (rate == null) return null;
  return idr * rate;
}

/// Konversi [amount] dari mata uang [from] ke [to] menggunakan kurs berbasis IDR.
double? convertCurrency(
  double amount,
  String from,
  String to,
  Map<String, double>? rates,
) {
  if (from == to) return amount;
  final idr = _foreignToIdrInline(amount, from, rates);
  if (idr == null) return null;
  return _idrToForeignInline(idr, to, rates);
}

/// Format uang sesuai kode mata uang.
/// Indonesia-style: IDR uses thousand sep "." and decimal sep ",".
String formatMoney(double amount, String code) {
  final info = supportedCurrencies[code];
  final decimals = info?.decimals ?? 2;
  final symbol = info?.symbol ?? '$code ';

  String numStr;
  if (decimals == 0) {
    numStr = amount.round().toString();
  } else {
    numStr = amount.toStringAsFixed(decimals);
  }

  final parts = numStr.split('.');
  final integerPart = parts[0];
  final decimalPart = parts.length > 1 ? parts[1] : '';

  final reversed = integerPart.split('').reversed.toList();
  final sb = StringBuffer();
  for (var i = 0; i < reversed.length; i++) {
    if (i > 0 && i % 3 == 0) sb.write('.');
    sb.write(reversed[i]);
  }
  final integerFormatted = sb.toString().split('').reversed.join();

  if (decimals == 0) {
    return code == 'IDR'
        ? '$symbol $integerFormatted'
        : '$symbol$integerFormatted';
  } else {
    return code == 'IDR'
        ? '$symbol $integerFormatted,$decimalPart'
        : '$symbol$integerFormatted,$decimalPart';
  }
}

/// Ringkasan total pengeluaran dalam mata uang tertentu.
class AwayDaySummary {
  const AwayDaySummary({
    required this.total,
    required this.totalIdr,
    required this.fallbackCount,
    required this.skippedCount,
    required this.currency,
  });

  final double total;
  final double totalIdr;
  final int fallbackCount;
  final int skippedCount;
  final String currency;
}

/// Ringkas semua pengeluaran ke mata uang output [outCurrency].
AwayDaySummary summarizeExpenses(
  List<AwayDayExpense> items,
  String outCurrency,
  Map<String, double>? rates,
) {
  var total = 0.0;
  var totalIdr = 0.0;
  var fallbackCount = 0;
  var skippedCount = 0;

  for (final item in items) {
    double? converted = convertCurrency(
      item.amountForeign,
      item.currencyCode,
      outCurrency,
      rates,
    );

    if (converted == null && item.amountIdr > 0) {
      converted = convertCurrency(item.amountIdr, 'IDR', outCurrency, rates);
      if (converted != null) {
        fallbackCount++;
      }
    }

    if (converted == null) {
      skippedCount++;
    } else {
      total += converted;
    }

    // totalIdr memakai logika yang sama tetapi menargetkan IDR.
    final idrForItem = convertCurrency(
          item.amountForeign,
          item.currencyCode,
          'IDR',
          rates,
        ) ??
        (item.amountIdr > 0 ? item.amountIdr : null);
    totalIdr += idrForItem ?? 0;
  }

  return AwayDaySummary(
    total: total,
    totalIdr: totalIdr,
    fallbackCount: fallbackCount,
    skippedCount: skippedCount,
    currency: outCurrency,
  );
}
