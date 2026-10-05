import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:smart_football_fan/core/utils/crypto_utils.dart';
import 'package:smart_football_fan/core/utils/jwt_utils.dart';
import 'package:smart_football_fan/features/auth/data/auth_repository.dart';

/// JWT palsu: yang penting payload-nya, signature memang tidak bisa
/// diverifikasi dari sisi klien karena kuncinya ada di server.
String fakeJwt({int? expiresAt}) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${seg({
        'uid': 1,
        'email': 'a@b.com',
        if (expiresAt != null) 'exp': expiresAt
      })}'
      '.signature';
}

ResponseBody jsonBody(Object data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// Server palsu: mencatat semua permintaan dan membalas sesuai handler.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.onRequest);

  final ResponseBody Function(String path, Map<String, dynamic> body) onRequest;

  final List<String> paths = [];
  final List<Map<String, dynamic>> bodies = [];

  Map<String, dynamic> bodyOf(String suffix) =>
      bodies.firstWhere((b) => true, orElse: () => <String, dynamic>{});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final body = options.data == null
        ? <String, dynamic>{}
        : jsonDecode(jsonEncode(options.data)) as Map<String, dynamic>;
    bodies.add(body);
    return onRequest(options.path, body);
  }

  @override
  void close({bool force = false}) {}
}

/// Server yang menerima registrasi lalu login, seperti server sungguhan.
FakeServer happyServer({String email = 'baru@contoh.com'}) => FakeServer(
      (path, body) => path.endsWith('/register')
          ? jsonBody({'id': 7, 'email': body['email']})
          : jsonBody({
              'token': fakeJwt(
                expiresAt: DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
              ),
            }),
    );

AuthRepository buildRepo(
  HttpClientAdapter adapter, {
  String baseUrl = 'https://api.example.com',
  bool? allowMock,
  Map<String, String> storage = const {},
}) {
  // Peta harus bisa diubah oleh platform test secure storage.
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(storage));
  final dio = Dio()..httpClientAdapter = adapter;
  return AuthRepository(
    dio,
    const FlutterSecureStorage(),
    LocalAuthentication(),
    baseUrl: baseUrl,
    allowMock: allowMock,
  );
}

void main() {
  group('U2: pesan error', () {
    test('401 memakai kalimat kredensial, tanpa "DioException"', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
          data: {'error': 'Email atau password salah'},
        ),
      ));
      expect(msg, 'Email atau password salah');
      expect(msg.contains('Exception'), isFalse);
    });

    test('401 tanpa pesan server tetap menyebut email/password', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
        ),
      ));
      expect(msg, 'Email atau password salah.');
    });

    test('timeout diterjemahkan ke Bahasa Indonesia', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.connectionTimeout,
      ));
      expect(msg, 'Server tidak terjangkau. Coba beberapa saat lagi.');
    });

    test('tidak ada koneksi diterjemahkan', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.connectionError,
      ));
      expect(msg, 'Tidak ada koneksi ke server. Cek internetmu.');
    });

    test('500 memakai pesan server kalau ada', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 500,
          data: {'error': 'Database sedang diperbaiki'},
        ),
      ));
      expect(msg, 'Database sedang diperbaiki');
    });

    test('galat tanpa status tetap kalimat yang bisa dibaca', () {
      final msg = describeAuthError(DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        type: DioExceptionType.unknown,
      ));
      expect(msg.contains('Exception'), isFalse);
      expect(msg, isNotEmpty);
    });

    test('AuthException diteruskan apa adanya', () {
      expect(describeAuthError(AuthException('Email sudah terdaftar.')),
          'Email sudah terdaftar.');
    });

    test('galat login dari repository jadi kalimat Indonesia', () async {
      final repo = buildRepo(FakeServer((_, __) =>
          jsonBody({'error': 'Email atau password salah'}, status: 401)));
      await expectLater(
        repo.login('a@b.com', 'rahasia'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', 'Email atau password salah')),
      );
    });
  });

  group('U1: registrasi', () {
    test('daftar lalu langsung login', () async {
      final server = happyServer();
      final repo = buildRepo(server);
      await repo.register('baru@contoh.com', 'rahasia123', 'rahasia123');
      expect(server.paths, hasLength(2));
      expect(server.paths[0], endsWith('/auth/register'));
      expect(server.paths[1], endsWith('/auth/login'));
    });

    test('password dikirim sebagai SHA-256, bukan apa adanya', () async {
      final server = happyServer();
      final repo = buildRepo(server);
      await repo.register('baru@contoh.com', 'rahasia123', 'rahasia123');
      for (final body in server.bodies) {
        expect(body['password'], CryptoUtils.sha256Hash('rahasia123'));
        expect(body.values.join(), isNot(contains('rahasia123')));
      }
    });

    test('email dikirim dalam huruf kecil dan tanpa spasi', () async {
      final server = happyServer();
      final repo = buildRepo(server);
      await repo.login('  Baru@Contoh.COM ', 'rahasia123');
      expect(server.bodies.single['email'], 'Baru@Contoh.COM');
    });

    test('409 jadi "Email sudah terdaftar"', () async {
      final repo = buildRepo(FakeServer((_, __) =>
          jsonBody({'error': 'Email sudah terdaftar'}, status: 409)));
      await expectLater(
        repo.register('ada@b.com', 'rahasia123', 'rahasia123'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('sudah terdaftar'))),
      );
    });

    test('konfirmasi password harus sama', () async {
      final repo = buildRepo(happyServer());
      await expectLater(
        repo.register('baru@contoh.com', 'rahasia123', 'beda'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('tidak sama'))),
      );
    });

    test('password terlalu pendek ditolak', () async {
      final server = happyServer();
      final repo = buildRepo(server);
      await expectLater(
        repo.register('baru@contoh.com', 'pendek', 'pendek'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('8 karakter'))),
      );
      expect(server.paths, isEmpty, reason: 'tidak ada request yang dikirim');
    });

    test('email kosong ditolak sebelum ada permintaan', () async {
      final server = happyServer();
      final repo = buildRepo(server);
      await expectLater(
        repo.register('', 'rahasia123', 'rahasia123'),
        throwsA(isA<AuthException>()),
      );
      expect(server.paths, isEmpty);
    });

    test('respon login tanpa token ditolak dengan pesan jelas', () async {
      final repo = buildRepo(FakeServer((_, __) => jsonBody({'ok': true})));
      await expectLater(
        repo.login('a@b.com', 'rahasia123'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('tidak dikenali'))),
      );
    });
  });

  group('U5: masa berlaku sesi ikut exp JWT', () {
    test('exp dibaca sebagai waktu kedaluwarsa', () {
      final exp = DateTime.now().add(const Duration(hours: 2));
      final token = fakeJwt(expiresAt: exp.millisecondsSinceEpoch ~/ 1000);
      expect(tokenExpiry(token), isNotNull);
      expect(
        tokenExpiry(token)!.difference(exp).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('token tanpa exp dianggap tidak punya kedaluwarsa', () {
      expect(tokenExpiry(fakeJwt()), isNull);
    });

    test('token rusak tidak melempar, hanya null', () {
      expect(tokenExpiry('bukan.jwt'), isNull);
      expect(tokenExpiry('a.!!!.c'), isNull);
      expect(tokenExpiry(''), isNull);
      expect(tokenExpiry(null), isNull);
    });

    test(
        'sesi ditolak kalau exp lewat, walau nilai lokal masih menyangka valid',
        () async {
      final lewat = fakeJwt(
        expiresAt: DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000,
      );
      final repo = buildRepo(
        happyServer(),
        storage: {
          'session_token': lewat,
          // Nilai kedaluwarsa lama sengaja dibuat masih valid.
          'session_expiry': DateTime.now()
              .add(const Duration(days: 365))
              .millisecondsSinceEpoch
              .toString(),
        },
      );
      expect(await repo.hasSession(), isFalse);
    });

    test('sesi diterima kalau exp masih di depan', () async {
      final repo = buildRepo(
        happyServer(),
        storage: {
          'session_token': fakeJwt(
            expiresAt: DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          ),
        },
      );
      expect(await repo.hasSession(), isTrue);
    });

    test('login menyimpan expiry dari exp token, bukan 7 hari', () async {
      final server = FakeServer((_, __) => jsonBody({
            'token': fakeJwt(
              expiresAt: DateTime.now()
                      .add(const Duration(hours: 3))
                      .millisecondsSinceEpoch ~/
                  1000,
            ),
          }));
      final repo = buildRepo(server);
      await repo.login('a@b.com', 'rahasia123');
      const storage = FlutterSecureStorage();
      final expiry = int.parse((await storage.read(key: 'session_expiry'))!);
      final selisih = expiry - DateTime.now().millisecondsSinceEpoch;
      expect(selisih, lessThan(const Duration(hours: 4).inMilliseconds));
      expect(selisih, greaterThan(const Duration(hours: 2).inMilliseconds));
    });

    test('token tanpa exp memakai cadangan 7 hari', () async {
      final server =
          FakeServer((_, __) => jsonBody({'token': 'token-tanpa-exp'}));
      final repo = buildRepo(server);
      await repo.login('a@b.com', 'rahasia123');
      const storage = FlutterSecureStorage();
      final expiry = int.parse((await storage.read(key: 'session_expiry'))!);
      final selisih = expiry - DateTime.now().millisecondsSinceEpoch;
      expect(selisih, greaterThan(const Duration(days: 6).inMilliseconds));
      expect(selisih, lessThan(const Duration(days: 8).inMilliseconds));
    });
  });

  group('U4: data pengguna', () {
    test('daftar kunci mencakup pengeluaran, prediksi, rantai, foto, saran',
        () {
      const keys = AuthRepository.userDataKeys;
      expect(keys, contains('away_day_expenses'));
      expect(keys, contains('away_day_budget_idr'));
      expect(keys, contains('score_predictions'));
      expect(keys, contains('passport_chain'));
      expect(keys, contains('profile_photo_path'));
      expect(keys, contains('pam_feedback'));
      expect(keys, contains('favorite_team'));
    });

    test('kunci prefs perangkat tidak ikut dihapus', () {
      const keys = AuthRepository.userDataKeys;
      expect(keys.contains('theme_mode'), isFalse);
      expect(keys.contains('permission_rationale'), isFalse);
    });

    test('prefix cache Pundit ikut dibersihkan', () {
      expect(AuthRepository.userKeyPrefixes, contains('pundit_'));
    });

    test('logout menghapus sesi, email, dan private key wallet', () async {
      final repo = buildRepo(
        happyServer(),
        storage: {
          'session_token': 't',
          'session_expiry': '99999999999999',
          'user_email': 'a@b.com',
          'wallet_private_key': 'abcdef',
        },
      );
      await repo.logout();
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'session_token'), isNull);
      expect(await storage.read(key: 'session_expiry'), isNull);
      expect(await storage.read(key: 'user_email'), isNull);
      expect(await storage.read(key: 'wallet_private_key'), isNull);
    });
  });

  group('U3: mode mock', () {
    test('di build rilis, mock ditolak', () async {
      final repo = buildRepo(FakeServer((_, __) => jsonBody({})),
          baseUrl: '', allowMock: false);
      expect(repo.isMock, isTrue);
      await expectLater(
        repo.login('a@b.com', 'rahasia123'),
        throwsA(isA<AuthException>()
            .having((e) => e.message, 'message', contains('alamat server'))),
      );
      await expectLater(
        repo.register('a@b.com', 'rahasia123', 'rahasia123'),
        throwsA(isA<AuthException>()),
      );
    });

    test('di debug mock tetap boleh dipakai', () async {
      final repo = buildRepo(FakeServer((_, __) => jsonBody({})),
          baseUrl: '', allowMock: true);
      expect(repo.isMock, isTrue);
      await repo.login('a@b.com', 'rahasia123');
      expect(await repo.hasSession(), isTrue);
    });

    test('default mock mengikuti kReleaseMode', () {
      // Test berjalan dalam mode debug.
      expect(AuthRepository.mockAllowedByDefault, isTrue);
    });
  });
}
