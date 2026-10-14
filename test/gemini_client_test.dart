import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/core/network/gemini_client.dart';

void main() {
  group('modelCandidates', () {
    test('urutan: configured, remembered, lalu fallbacks', () {
      final out = modelCandidates(
        configured: 'a',
        remembered: 'b',
        fallbacks: const ['c', 'd'],
      );
      expect(out, ['a', 'b', 'c', 'd']);
    });

    test('duplikat dibuang tapi urutan pertama dipertahankan', () {
      final out = modelCandidates(
        configured: 'a',
        remembered: 'a',
        fallbacks: const ['a', 'b', 'b'],
      );
      expect(out, ['a', 'b']);
    });

    test('string kosong dan spasi dibuang', () {
      final out = modelCandidates(
        configured: '',
        remembered: '   ',
        fallbacks: const ['', 'x', '  '],
      );
      expect(out, ['x']);
    });

    test('tanpa remembered, fallbacks tetap ikut', () {
      final out = modelCandidates(
        configured: 'a',
        fallbacks: const ['b'],
      );
      expect(out, ['a', 'b']);
    });
  });

  group('geminiFailure', () {
    test('404 menandai model tidak tersedia', () {
      final e = geminiFailure(statusCode: 404);
      expect(e.modelUnavailable, isTrue);
      expect(e.statusCode, 404);
      expect(e.message, 'Model tidak tersedia');
    });

    test('401 menyebut API key tidak valid', () {
      final e = geminiFailure(statusCode: 401);
      expect(e.modelUnavailable, isFalse);
      expect(e.message, contains('API key'));
    });

    test('429 menyebut kuota atau batas permintaan', () {
      final e = geminiFailure(statusCode: 429);
      expect(e.message.toLowerCase(), contains('kuota'));
    });

    test('503 menyebut server sibuk', () {
      final e = geminiFailure(statusCode: 503);
      expect(e.message.toLowerCase(), contains('sibuk'));
    });

    test('timeout memakai pesan batas waktu', () {
      final e = geminiFailure(type: DioExceptionType.connectionTimeout);
      expect(e.message, 'Permintaan ke AI melewati batas waktu');
    });

    test('tanpa koneksi memakai pesan jaringan', () {
      final e = geminiFailure(type: DioExceptionType.connectionError);
      expect(e.message.toLowerCase(), contains('koneksi'));
    });
  });

  group('parseGeminiText', () {
    test('menggabung parts teks normal', () {
      final body = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Halo '},
                {'text': 'dunia'},
              ],
            },
          },
        ],
      };
      expect(parseGeminiText(body), 'Halo dunia');
    });

    test('mengabaikan part dengan thought == true', () {
      final body = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'berpikir...', 'thought': true},
                {'text': 'Jawaban'},
              ],
            },
          },
        ],
      };
      expect(parseGeminiText(body), 'Jawaban');
    });

    test('tanpa teks mengembalikan null', () {
      final body = {
        'candidates': [
          {
            'content': {'parts': <Object?>[]},
          },
        ],
      };
      expect(parseGeminiText(body), isNull);
    });

    test('body rusak mengembalikan null', () {
      expect(parseGeminiText(null), isNull);
      expect(parseGeminiText('bukan map'), isNull);
      expect(parseGeminiText(const <String, Object?>{}), isNull);
      expect(parseGeminiText({'candidates': 'bukan list'}), isNull);
      expect(parseGeminiText({'candidates': const []}), isNull);
    });
  });
}
