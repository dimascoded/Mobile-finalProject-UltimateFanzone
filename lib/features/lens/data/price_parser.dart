import 'dart:math';

class DetectedPrice {
  const DetectedPrice(this.line, this.amount);
  final String line;
  final double amount;
}

/// Mengekstrak angka harga dari teks hasil OCR (Dart murni -> mudah di-unit-test).
class PriceParser {
  /// Mata uang tanpa pecahan: '.' dan ',' selalu pemisah ribuan.
  static const zeroDecimal = {'JPY', 'KRW'};
  static final _number = RegExp(r'\d[\d.,]*\d|\d');

  static List<DetectedPrice> extract(String text, String currency) {
    final out = <DetectedPrice>[];
    final seen = <String>{};
    for (final line in text.split('\n')) {
      for (final m in _number.allMatches(line)) {
        final raw = m.group(0)!;
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length > 7) continue; // kemungkinan nomor telepon/kode
        final v = parse(raw, currency);
        if (v == null || v <= 0) continue;
        if (seen.add('${line.trim()}|$v')) {
          out.add(DetectedPrice(line.trim(), v));
        }
      }
    }
    return out;
  }

  static double? parse(String raw, String currency) {
    final stripAll = raw.replaceAll(RegExp(r'[.,]'), '');
    if (zeroDecimal.contains(currency)) return double.tryParse(stripAll);

    final sep = max(raw.lastIndexOf('.'), raw.lastIndexOf(','));
    if (sep == -1) return double.tryParse(raw);
    final decimals = raw.length - sep - 1;
    if (decimals == 1 || decimals == 2) {
      final intPart = raw.substring(0, sep).replaceAll(RegExp(r'[.,]'), '');
      return double.tryParse('$intPart.${raw.substring(sep + 1)}');
    }
    return double.tryParse(stripAll);
  }
}
