import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';

void main() {
  group('pemetaan galat Supabase Auth', () {
    test('invalid_credentials -> Email atau password salah.', () {
      expect(
        describeAuthError(const supa.AuthException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        )),
        'Email atau password salah.',
      );
    });

    test('pesan "Invalid login credentials" tanpa code', () {
      expect(
        describeAuthError(const supa.AuthException('Invalid login credentials')),
        'Email atau password salah.',
      );
    });

    test('email_not_confirmed -> minta verifikasi email', () {
      expect(
        describeAuthError(const supa.AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        )),
        'Email belum diverifikasi. Cek kotak masuk emailmu.',
      );
    });

    test('user_already_exists -> suruh masuk', () {
      expect(
        describeAuthError(const supa.AuthException(
          'User already registered',
          statusCode: '400',
          code: 'user_already_exists',
        )),
        'Email sudah terdaftar. Silakan masuk.',
      );
    });

    test('pesan "already registered" tanpa code', () {
      expect(
        describeAuthError(const supa.AuthException('User already registered')),
        'Email sudah terdaftar. Silakan masuk.',
      );
    });

    test('over_request_rate_limit -> minta tunggu', () {
      expect(
        describeAuthError(const supa.AuthException(
          'Too many requests',
          statusCode: '429',
          code: 'over_request_rate_limit',
        )),
        'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.',
      );
    });

    test('over_email_send_rate_limit -> minta tunggu', () {
      expect(
        describeAuthError(const supa.AuthException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        )),
        'Terlalu banyak percobaan. Tunggu beberapa menit lalu coba lagi.',
      );
    });

    test('weak_password -> minta password lebih kuat', () {
      expect(
        describeAuthError(const supa.AuthException(
          'Weak password',
          statusCode: '422',
          code: 'weak_password',
        )),
        'Password terlalu lemah. Gunakan minimal 8 karakter.',
      );
    });

    test('pesan lain diteruskan apa adanya', () {
      expect(
        describeAuthError(const supa.AuthException('Kesalahan tak terduga')),
        'Kesalahan tak terduga',
      );
    });

    test('pesan kosong memakai fallback Gagal masuk.', () {
      expect(describeAuthError(const supa.AuthException('')), 'Gagal masuk.');
    });
  });

  group('pemetaan galat jaringan', () {
    test('SocketException -> tidak ada koneksi', () {
      expect(
        describeAuthError(const SocketException('failed')),
        'Tidak ada koneksi ke server. Cek internetmu.',
      );
    });

    test('Dio connectionError -> tidak ada koneksi', () {
      expect(
        describeAuthError(DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionError,
        )),
        'Tidak ada koneksi ke server. Cek internetmu.',
      );
    });

    test('Dio connectionTimeout -> tidak ada koneksi', () {
      expect(
        describeAuthError(DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionTimeout,
        )),
        'Tidak ada koneksi ke server. Cek internetmu.',
      );
    });
  });

  group('galat lain', () {
    test('AuthException diteruskan apa adanya', () {
      expect(
        describeAuthError(AuthException('Email sudah terdaftar.')),
        'Email sudah terdaftar.',
      );
    });

    test('galat umum tetap kalimat yang bisa dibaca', () {
      expect(describeAuthError(Exception('sesuatu')), 'sesuatu');
    });
  });
}
