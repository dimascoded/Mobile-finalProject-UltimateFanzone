import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Klien HTTP bersama untuk seluruh lapisan jaringan.
///
/// Menyediakan satu instance [Dio] yang dipakai bersama lewat [dioProvider],
/// sehingga interceptor, timeout, dan konfigurasi lain cukup diatur di satu
/// tempat.
///
/// Timeout dibatasi 10 detik untuk koneksi dan 15 detik untuk penerimaan
/// respons agar UI tidak menggantung saat jaringan buruk. Tidak ada API key
/// atau rahasia yang ditulis langsung di sini; header autentikasi disetel di
/// lapisan repository masing-masing.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));
  dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
  return dio;
});
