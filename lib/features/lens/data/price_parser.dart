import 'dart:math';

/// Satu harga yang terdeteksi dari teks OCR.
///
/// [line] menyimpan baris asal supaya UI bisa menampilkan kandidat lengkap
/// ("Total £52.50"), bukan cuma angkanya.
class DetectedPrice {
  /// Membuat kandidat harga.
  const DetectedPrice(this.line, this.amount);

  /// Baris teks OCR tempat harga ditemukan.
  final String line;

  /// Nilai harga hasil parse (tanpa simbol mata uang).
  final double amount;
}

/// Mengekstrak angka harga dari teks hasil OCR (Dart murni -> mudah di-unit-test).
class PriceParser {
  /// Mata uang tanpa pecahan: '.' dan ',' selalu pemisah ribuan.
  ///
  /// JPY dan KRW tidak memakai sen, jadi `1,234` berarti seribu tiga ratus
  /// empat puluh tiga — bukan 1,23.
  static const zeroDecimal = {'JPY', 'KRW'};

  /// Pola angka: digit, lalu digit/pemisah, lalu digit (atau satu digit saja).
  static final _number = RegExp(r'\d[\d.,]*\d|\d');

  /// Ekstrak semua kandidat harga dari [text] untuk mata uang [currency].
  ///
  /// Baris diproses satu per satu; setiap angka yang ditemukan di-parse.
  /// Angka dengan lebih dari 7 digit dilewati (kemungkinan nomor telepon atau
  /// kode), dan kandidat duplikat pada baris yang sama dibuang. Hasilnya
  /// tetap bisa berisi lebih dari satu nilai per baris.
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

  /// Ubah potongan angka mentah dari OCR menjadi nilai desimal.
  ///
  /// Aturan untuk mata uang berdesimal (GBP/USD/EUR):
  /// - Pemisah desimal dianggap sebagai titik OR koma TERAKHIR yang diikuti
  ///   1 atau 2 digit. Jadi `1,234.56` (format Inggris) dan `1.234,56`
  ///   (format Indonesia/Eropa) sama-sama menghasilkan 1234.56.
  /// - Kalau tidak ada pemisah, atau pemisah diikuti lebih dari 2 digit,
  ///   semua titik dan koma dianggap pemisah ribuan: `1.234` -> 1234.
  ///
  /// Untuk mata uang tanpa pecahan ([zeroDecimal], mis. JPY/KRW) semua titik
  /// dan koma dibuang sebagai pemisah ribuan: `1,234` -> 1234.
  ///
  /// Mengembalikan null kalau teksnya bukan angka yang valid.
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
