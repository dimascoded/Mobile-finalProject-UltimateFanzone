import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/auth/presentation/lock_screen.dart';

/// Repositori palsu: tidak menyentuh Supabase/secure storage, cukup mencatat
/// pemanggilan supaya bisa dipastikan "Gunakan password" TIDAK memanggil
/// logout (data pengguna tidak boleh terhapus).
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(const FlutterSecureStorage(), LocalAuthentication());

  int verifyCalls = 0;
  int logoutCalls = 0;
  String? lastPassword;
  bool failVerify = false;

  @override
  Future<bool> canUseBiometric() async => true;

  @override
  Future<bool> authenticateBiometric() async {
    // Gagal cepat supaya LockScreen tidak otomatis terbuka dan tombol
    // "Gunakan password" tetap bisa ditekan.
    throw AuthException('Autentikasi biometrik gagal.');
  }

  @override
  Future<void> verifyPassword(String password) async {
    verifyCalls++;
    lastPassword = password;
    if (failVerify) throw AuthException('Email atau password salah.');
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('lock_fallback');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('lock_fallback_test');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpLock(WidgetTester tester, _FakeAuthRepository fake) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LockScreen(popOnSuccess: true),
                    ),
                  ),
                  child: const Text('buka kunci'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka kunci'));
    await tester.pumpAndSettle();
    expect(find.text('Aplikasi terkunci'), findsOneWidget);
  }

  testWidgets('password salah menampilkan pesan dan tidak menghapus data',
      (tester) async {
    final fake = _FakeAuthRepository()..failVerify = true;
    await pumpLock(tester, fake);

    await tester.tap(find.text('Gunakan password'));
    await tester.pumpAndSettle();
    expect(find.text('Masuk dengan password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'salah');
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(find.text('Email atau password salah.'), findsOneWidget);
    expect(fake.verifyCalls, 1);
    expect(fake.logoutCalls, 0);
  });

  testWidgets('password benar membuka kunci tanpa logout', (tester) async {
    final fake = _FakeAuthRepository();
    await pumpLock(tester, fake);

    await tester.tap(find.text('Gunakan password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rahasia');
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    expect(fake.verifyCalls, 1);
    expect(fake.lastPassword, 'rahasia');
    expect(fake.logoutCalls, 0);
    // LockScreen ter-pop, kembali ke layar pemanggil.
    expect(find.text('buka kunci'), findsOneWidget);
  });
}
