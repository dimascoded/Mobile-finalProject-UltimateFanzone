import 'away_day_repository.dart';

/// Informasi mata uang yang didukung.
///
/// [decimals] menentukan jumlah angka di belakang koma saat format uang
/// ditampilkan: 0 untuk Rupiah (IDR), 2 untuk GBP/USD/EUR.
class CurrencyInfo {
  /// Membuat metadata mata uang.
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.decimals,
    required this.name,
  });

  /// Kode ISO mata uang (mis. `GBP`).
  final String code;

  /// Simbol yang dipakai saat menampilkan nominal.
  final String symbol;

  /// Jumlah desimal untuk format tampilan (0 atau 2).
  final int decimals;

  /// Nama mata uang dalam Bahasa Indonesia.
  final String name;
}

/// Daftar mata uang yang didukung untuk Away Day.
///
/// Kunci `IDR` memiliki 0 desimal (Rupiah tidak memakai pecahan), sedangkan
/// mata uang asing memakai 2 desimal.
const supportedCurrencies = <String, CurrencyInfo>{
  'GBP': CurrencyInfo(
      code: 'GBP', symbol: '\u00A3', decimals: 2, name: 'Poundsterling'),
  'USD': CurrencyInfo(code: 'USD', symbol: '\$', decimals: 2, name: 'Dolar AS'),
  'EUR': CurrencyInfo(code: 'EUR', symbol: '\u20AC', decimals: 2, name: 'Euro'),
  'IDR': CurrencyInfo(code: 'IDR', symbol: 'Rp', decimals: 0, name: 'Rupiah'),
};

/// Konversi mata uang asing ke Rupiah dengan kurs berbasis IDR.
///
/// PENTING: kurs dari exchangerate-api.com diambil dengan basis `IDR`, jadi
/// `rates['GBP']` berarti "GBP per 1 Rupiah". Karena itu nominal asing ke
/// Rupiah itu DIBAGI (`amount / rate`), bukan dikali.
///
/// Mengembalikan null bila kurs untuk [currency] tidak ada atau bernilai 0.
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

/// Konversi Rupiah ke mata uang asing dengan kurs berbasis IDR.
///
/// Sebaliknya dari [_foreignToIdrInline]: karena `rates[code]` adalah unit
/// asing per 1 Rupiah, konversi ke asing itu DIKALI (`idr * rate`).
///
/// Mengembalikan null bila kurs untuk [currency] tidak ada.
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
///
/// Alur: [from] → IDR (dibagi kurs) → [to] (dikali kurs). Mengembalikan
/// `amount` langsung bila [from] == [to], dan null bila kurs untuk salah satu
/// mata uang tidak tersedia.
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
///
/// Pemisah ribuan memakai titik dan pemisah desimal memakai koma untuk semua
/// mata uang; IDR dibulatkan ke integer (0 desimal) dan diberi spasi setelah
/// simbol ("Rp 1.234"), mata uang asing tidak memakai spasi ("£1.234,56").
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
///
/// [total] adalah jumlah dalam [currency] tampilan, [totalIdr] adalah jumlah
/// yang sama dalam Rupiah. [fallbackCount] menghitung pengeluaran yang
/// dikonversi lewat [AwayDayExpense.amountIdr] karena kurs mata uang aslinya
/// tidak ada; [skippedCount] menghitung pengeluaran yang tidak bisa
/// dikonversi sama sekali dan tidak ikut masuk total.
class AwayDaySummary {
  /// Membuat ringkasan.
  const AwayDaySummary({
    required this.total,
    required this.totalIdr,
    required this.fallbackCount,
    required this.skippedCount,
    required this.currency,
  });

  /// Total dalam mata uang output.
  final double total;

  /// Total dalam Rupiah.
  final double totalIdr;

  /// Jumlah item yang memakai nilai Rupiah tersimpan sebagai cadangan.
  final int fallbackCount;

  /// Jumlah item yang tidak bisa dikonversi dan tidak dihitung.
  final int skippedCount;

  /// Kode mata uang output.
  final String currency;
}

/// Ringkas semua pengeluaran ke mata uang output [outCurrency].
///
/// Konversi memakai kurs berbasis IDR (lihat [convertCurrency]): nominal
/// asing ke Rupiah dibagi kurs, Rupiah ke asing dikali kurs. Bila kurs mata
/// uang asli item tidak ada, [AwayDayExpense.amountIdr] dipakai sebagai
/// cadangan (dihitung di [fallbackCount]); item tanpa cadangan diabaikan
/// (dihitung di [skippedCount]).
///
/// [totalIdr] selalu memakai jalur yang sama dengan [total], dituju ke IDR.
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
