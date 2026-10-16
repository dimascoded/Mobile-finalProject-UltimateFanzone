import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/network/gemini_client.dart';

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

  group('GeminiClient retry & perpindahan model', () {
    test('503 lalu 200 pada model sama: tepat 2 permintaan', () async {
      var calls = 0;
      final adapter = _FakeAdapter((options) async {
        calls++;
        return calls == 1 ? _errorResponse(503) : _textResponse('halo');
      });
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      final res = await client.generate(
        apiKey: 'k',
        prompt: 'p',
        models: const ['model-a'],
      );

      expect(res.text, 'halo');
      expect(res.model, 'model-a');
      expect(adapter.requests.length, 2);
    });

    test('503 tiga kali pada model A lalu 200 pada model B', () async {
      final adapter = _FakeAdapter((options) async {
        if (_modelOf(options) == 'model-a') return _errorResponse(503);
        return _textResponse('dari-b');
      });
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      final res = await client.generate(
        apiKey: 'k',
        prompt: 'p',
        models: const ['model-a', 'model-b'],
      );

      expect(res.text, 'dari-b');
      expect(res.model, 'model-b');
      expect(
        adapter.requests.where((o) => _modelOf(o) == 'model-a').length,
        3,
      );
      expect(
        adapter.requests.where((o) => _modelOf(o) == 'model-b').length,
        1,
      );
    });

    test('404 pada model A langsung pindah ke model B', () async {
      final adapter = _FakeAdapter((options) async {
        if (_modelOf(options) == 'model-a') return _errorResponse(404);
        return _textResponse('dari-b');
      });
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      final res = await client.generate(
        apiKey: 'k',
        prompt: 'p',
        models: const ['model-a', 'model-b'],
      );

      expect(res.text, 'dari-b');
      expect(res.model, 'model-b');
      expect(
        adapter.requests.where((o) => _modelOf(o) == 'model-a').length,
        1,
      );
    });

    test('401 gagal setelah tepat 1 permintaan dengan pesan API key', () async {
      final adapter = _FakeAdapter((options) async => _errorResponse(401));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      await expectLater(
        client.generate(
          apiKey: 'k',
          prompt: 'p',
          models: const ['model-a', 'model-b'],
        ),
        throwsA(
          isA<GeminiException>()
              .having((e) => e.message, 'message', contains('API key')),
        ),
      );
      expect(adapter.requests.length, 1);
    });

    test('Retry-After: 2 dihormati', () async {
      final delays = <Duration>[];
      var calls = 0;
      final adapter = _FakeAdapter((options) async {
        calls++;
        if (calls == 1) {
          return _errorResponse(503, headers: const {
            'retry-after': ['2'],
          });
        }
        return _textResponse('ok');
      });
      final client = GeminiClient(
        dio: _dioWith(adapter),
        sleep: (d) async => delays.add(d),
      );

      final res = await client.generate(
        apiKey: 'k',
        prompt: 'p',
        models: const ['model-a'],
      );

      expect(res.text, 'ok');
      expect(delays, [const Duration(seconds: 2)]);
    });

    test('Retry-After: 60 dibatasi 8 detik', () async {
      final delays = <Duration>[];
      final adapter = _FakeAdapter(
        (options) async => _errorResponse(503, headers: const {
          'retry-after': ['60'],
        }),
      );
      final client = GeminiClient(
        dio: _dioWith(adapter),
        sleep: (d) async => delays.add(d),
      );

      await expectLater(
        client.generate(apiKey: 'k', prompt: 'p', models: const ['model-a']),
        throwsA(
          isA<GeminiException>().having(
              (e) => e.message.toLowerCase(), 'message', contains('sibuk')),
        ),
      );
      expect(delays, [const Duration(seconds: 8), const Duration(seconds: 8)]);
    });

    test('semua model 503 -> GeminiException pesan sibuk', () async {
      final adapter = _FakeAdapter((options) async => _errorResponse(503));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      await expectLater(
        client.generate(
          apiKey: 'k',
          prompt: 'p',
          models: const ['model-a', 'model-b'],
        ),
        throwsA(
          isA<GeminiException>().having(
              (e) => e.message.toLowerCase(), 'message', contains('sibuk')),
        ),
      );
      expect(adapter.requests.length, 6);
    });
  });

  group('GeminiClient.chat', () {
    test('body memuat systemInstruction dan role bergantian', () async {
      final adapter = _FakeAdapter((options) async => _textResponse('jawab'));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      final res = await client.chat(
        apiKey: 'k',
        systemInstruction: 'Instruksi sistem',
        turns: const [
          ChatTurn(role: 'user', text: 'hai'),
          ChatTurn(role: 'model', text: 'halo'),
          ChatTurn(role: 'user', text: 'lagi'),
        ],
        models: const ['model-a'],
      );

      expect(res.text, 'jawab');
      expect(adapter.requests.length, 1);
      final body = adapter.requests.single.data as Map;
      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'Instruksi sistem'},
        ],
      });
      final contents = body['contents'] as List;
      expect(contents.map((c) => (c as Map)['role']).toList(),
          ['user', 'model', 'user']);
      expect((contents.first as Map)['parts'], [
        {'text': 'hai'},
      ]);
    });

    test('turns kosong ditolak', () async {
      final adapter = _FakeAdapter((options) async => _textResponse('x'));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      await expectLater(
        client.chat(
          apiKey: 'k',
          systemInstruction: 's',
          turns: const [],
          models: const ['model-a'],
        ),
        throwsA(isA<GeminiException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('giliran pertama bukan user ditolak', () async {
      final adapter = _FakeAdapter((options) async => _textResponse('x'));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      await expectLater(
        client.chat(
          apiKey: 'k',
          systemInstruction: 's',
          turns: const [ChatTurn(role: 'model', text: 'halo')],
          models: const ['model-a'],
        ),
        throwsA(isA<GeminiException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('giliran terakhir role model ditolak', () async {
      final adapter = _FakeAdapter((options) async => _textResponse('x'));
      final client = GeminiClient(dio: _dioWith(adapter), sleep: (_) async {});

      await expectLater(
        client.chat(
          apiKey: 'k',
          systemInstruction: 's',
          turns: const [
            ChatTurn(role: 'user', text: 'hai'),
            ChatTurn(role: 'model', text: 'halo'),
          ],
          models: const ['model-a'],
        ),
        throwsA(isA<GeminiException>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });
}

Dio _dioWith(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

String _modelOf(RequestOptions options) {
  final match = RegExp(r'/models/([^/:]+):').firstMatch(options.path);
  return match?.group(1) ?? '';
}

ResponseBody _textResponse(String text) => ResponseBody.fromString(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      }),
      200,
      headers: const {
        'content-type': ['application/json']
      },
    );

ResponseBody _errorResponse(int status, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode({
        'error': {'code': status},
      }),
      status,
      headers: {
        'content-type': const ['application/json'],
        ...?headers,
      },
    );

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
