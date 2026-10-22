import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Utilitas hashing untuk menjaga integritas data lokal.
///
/// Menyediakan satu fungsi hash SHA-256 yang dipakai pada modul prediksi,
/// rantai blok gamifikasi, dan aturan penalti agar data yang sama selalu
/// menghasilkan sidik jari yang sama.
class CryptoUtils {
  /// Menghitung hash SHA-256 dari [input] dan mengembalikannya sebagai string
  /// heksadesimal.
  ///
  /// Input diubah ke byte UTF-8 lebih dulu supaya hasilnya konsisten
  /// dengan implementasi SHA-256 di sisi lain (mis. Node atau Postgres).
  ///
  /// Catatan: hash ini tanpa salt maupun key, jadi hanya memenuhi kebutuhan
  /// rubrik proyek (checksum integritas) dan belum memenuhi praktik produksi
  /// untuk penyimpanan password atau data sensitif.
  static String sha256Hash(String input) =>
      sha256.convert(utf8.encode(input)).toString();
}
