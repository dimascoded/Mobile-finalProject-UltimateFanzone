import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/sync/data/sync_repository.dart';

/// Adapter yang menjawab dari dalam memory, tanpa jaringan.
///
/// Meniru server sungguhan: POST /sync membalas jumlah per koleksi, GET /sync
/// membalas daftar isinya.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({this.onPost, this.onGet, this.onAny});

  final ResponseBody Function(Map<String, dynamic> body)? onPost;
  final ResponseBody Function()? onGet;
  final ResponseBody Function(String path)? onAny;

  /// Body request terakhir, jadi isi payload bisa diperiksa.
  Map<String, dynamic>? lastBody;
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    if (options.data != null) {
      lastBody = jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
    }
    if (onAny != null) return onAny!(options.path);
    if (options.method == 'POST') {
      return onPost?.call(lastBody ?? const {}) ??
          json200({'expenses': 0, 'chain': 0, 'predictions': 0, 'feedback': 0});
    }
    return onGet?.call() ?? json200(const {});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json200(Object data) => ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

ResponseBody jsonError(int code, String message) => ResponseBody.fromString(
      jsonEncode({'error': message}),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

SyncRepository buildRepo(
  HttpClientAdapter adapter, {
  String? token = 'token-abc',
  String baseUrl = 'https://api.example.com',
}) {
  final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500))
    ..httpClientAdapter = adapter;
  final auth = AuthRepository(
      const FlutterSecureStorage(), LocalAuthentication());
  return SyncRepository(
    dio,
    auth,
    baseUrl: baseUrl,
    tokenLoader: () async => token,
  );
}

Prediction prediction(int matchId, int home, int away) => Prediction(
      matchId: matchId,
      homeScore: home,
      awayScore: away,
      salt: 'salt$matchId',
      commit: 'commit$matchId',
      createdAt: DateTime.utc(2026, 8, 15, 14),
    );

Map<String, dynamic> resultBlock(int matchId) => {
      'index': 2,
      'timestamp': 1,
      'type': Prediction.blockTypeResult,
      'data': {'match': matchId, 'salt': 'x'},
      'owner': 'me',
      'prevHash': 'p',
      'nonce': 1,
      'hash': 'h',
    };

void main() {
  group('cloud belum dikonfigurasi', () {
    test('mengembalikan daftar lokal, jadi Hive tidak dikosongkan', () async {
      final lokal = [prediction(7001, 2, 1)];
      final repo = buildRepo(
        FakeAdapter(),
        baseUrl: '', // tanpa server = sinkronisasi dilewati
      );
      final hasil = await repo.sync(
        expenses: const [],
        chain: const [],
        predictions: lokal,
      );
      expect(hasil.predictions.length, 1);
      expect(hasil.predictions.first.matchId, 7001);
      expect(hasil.mergedPredictions, 1);
    });
  });

  group('isi payload push prediksi', () {
    test('tanpa blok result tetap bentuk penuh (skor + salt)', () async {
      final adapter = FakeAdapter(
          onPost: (b) => json200({
                'expenses': (b['expenses'] as List).length,
                'chain': (b['chain'] as List).length,
                'predictions': (b['predictions'] as List).length,
              }));
      final repo = buildRepo(adapter);
      await repo.sync(
        expenses: const [],
        chain: const [],
        predictions: [prediction(7001, 2, 1)],
      );
      final sent = (adapter.lastBody!['predictions'] as List).single as Map;
      expect(sent['matchId'], 7001);
      expect(sent['homeScore'], 2);
      expect(sent['awayScore'], 1);
      expect(sent['salt'], 'salt7001');
      expect(sent['commit'], 'commit7001');
    });

    test('ada blok result, tetap bentuk penuh', () async {
      final adapter = FakeAdapter(
          onPost: (b) =>
              json200({'predictions': (b['predictions'] as List).length}));
      final repo = buildRepo(adapter);
      await repo.sync(
        expenses: const [],
        chain: [resultBlock(7001)],
        predictions: [prediction(7001, 2, 1)],
      );
      final sent = (adapter.lastBody!['predictions'] as List).single as Map;
      expect(sent['salt'], 'salt7001');
      expect(sent['homeScore'], 2);
    });

    test('perangkat yang menulis ke /sync lalu menarik /sync', () async {
      final adapter = FakeAdapter();
      final repo = buildRepo(adapter, token: 'jwt-123');
      await repo
          .sync(expenses: const [], chain: const [], predictions: const []);
      expect(adapter.lastPath, endsWith('/sync'));
    });
  });

  group('S1: pull lalu merge', () {
    test('hasil pull server digabung dengan data lokal', () async {
      final adapter = FakeAdapter(
          onGet: () => json200({
                'expenses': const [],
                'chain': const [],
                'predictions': const [],
              }));
      final repo = buildRepo(adapter);
      final hasil = await repo.sync(
        expenses: const [],
        chain: const [],
        predictions: [prediction(7001, 2, 1)],
      );
      expect(hasil.mergedPredictions, 1);
      expect(hasil.predictions.first.salt, 'salt7001');
    });
  });

  group('S3: penanganan galat', () {
    test('tanpa token ditolak sebelum request', () async {
      final adapter = FakeAdapter();
      final repo = buildRepo(adapter, token: '');
      await expectLater(
        repo.sync(expenses: const [], chain: const [], predictions: const []),
        throwsA(isA<SyncException>()
            .having((e) => e.message, 'message', contains('Belum login'))),
      );
      expect(adapter.lastPath, isNull,
          reason: 'tidak ada request yang dikirim');
    });

    test('401 ditandai unauthorized supaya pemanggil logout', () async {
      final adapter =
          FakeAdapter(onPost: (_) => jsonError(401, 'token kedaluwarsa'));
      final repo = buildRepo(adapter);
      await expectLater(
        repo.sync(expenses: const [], chain: const [], predictions: const []),
        throwsA(isA<SyncException>()
            .having((e) => e.unauthorized, 'unauthorized', isTrue)
            .having((e) => e.message, 'message', 'token kedaluwarsa')),
      );
    });

    test('500 tanpa pesan memakai kalimat bawaan', () async {
      final adapter = FakeAdapter(onPost: (_) => jsonError(500, ''));
      final repo = buildRepo(adapter);
      await expectLater(
        repo.sync(expenses: const [], chain: const [], predictions: const []),
        throwsA(isA<SyncException>()
            .having((e) => e.unauthorized, 'unauthorized', isFalse)
            .having((e) => e.message, 'message',
                contains('Server menolak pencadangan (500)'))),
      );
    });

    test('respons bukan objek ditolak dengan pesan jelas', () async {
      final adapter = FakeAdapter(
          onPost: (_) => ResponseBody.fromString('[1,2,3]', 200, headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              }));
      final repo = buildRepo(adapter);
      await expectLater(
        repo.sync(expenses: const [], chain: const [], predictions: const []),
        throwsA(isA<SyncException>()
            .having((e) => e.message, 'message', contains('tidak dikenali'))),
      );
    });
  });
}
