import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/auth/providers/auth_provider.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/widgets/profile_header.dart';
import 'package:ultimate_fanzone/features/dashboard/providers/dashboard_provider.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';

/// Repositori palsu: mencatat nama yang disimpan dan mengembalikan nama cloud
/// buatan, tanpa menyentuh Supabase maupun secure storage.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({String? cloudName})
      : _cloudName = cloudName,
        super(const FlutterSecureStorage(), LocalAuthentication());

  final String? _cloudName;
  final List<String> savedNames = [];

  @override
  String? cloudDisplayName() => _cloudName;

  @override
  Future<void> saveDisplayName(String name) async {
    savedNames.add(name);
  }

  @override
  Future<void> logout() async {}
}

void main() {
  group('validateDisplayName', () {
    test('string kosong dan satu karakter ditolak', () {
      expect(validateDisplayName(''), 'Nama minimal 2 karakter');
      expect(validateDisplayName('a'), 'Nama minimal 2 karakter');
      expect(validateDisplayName('   '), 'Nama minimal 2 karakter');
    });

    test('dua karakter setelah trim valid', () {
      expect(validateDisplayName('  ab  '), isNull);
    });

    test('31 karakter ditolak, 30 valid', () {
      expect(validateDisplayName('a' * 31), 'Nama maksimal 30 karakter');
      expect(validateDisplayName('a' * 30), isNull);
    });

    test('spasi berturut-turut dijadikan satu (validasi lolos)', () {
      // 'Budi   Santoso' menjadi 'Budi Santoso' (12 karakter) -> valid.
      expect(validateDisplayName('Budi   Santoso'), isNull);
    });

    test('karakter kontrol ditolak', () {
      expect(validateDisplayName('Bu\x00di'), isNotNull);
    });
  });

  group('DisplayNameNotifier', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sgt_display_name');
      Hive.init(dir.path);
      HiveService.cache = await Hive.openBox<String>('display_name_box');
    });

    tearDown(() async {
      await HiveService.cache.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('set() menyimpan ke Hive, memperbarui state, dan memanggil cloud',
        () async {
      final repo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final error = await container
          .read(displayNameProvider.notifier)
          .set('  Budi   Santoso  ');

      expect(error, isNull);
      expect(container.read(displayNameProvider), 'Budi Santoso');
      expect(HiveService.cache.get(displayNameHiveKey), 'Budi Santoso');
      expect(repo.savedNames, ['Budi Santoso']);
    });

    test('set() menolak input tidak valid tanpa menyimpan', () async {
      final repo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final error = await container.read(displayNameProvider.notifier).set('a');

      expect(error, 'Nama minimal 2 karakter');
      expect(container.read(displayNameProvider), isNull);
      expect(HiveService.cache.get(displayNameHiveKey), isNull);
      expect(repo.savedNames, isEmpty);
    });

    test('logout menginvalidate displayNameProvider', () async {
      final repo = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(displayNameProvider.notifier).set('Budi');
      expect(container.read(displayNameProvider), 'Budi');

      await container.read(logoutProvider)();

      // Hive sudah dibersihkan clearUserData + provider di-invalidate, jadi
      // notifier dibuat ulang dan memuat null.
      expect(container.read(displayNameProvider), isNull);
    });
  });

  group('effectiveDisplayNameProvider', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sgt_effective_name');
      Hive.init(dir.path);
      HiveService.cache = await Hive.openBox<String>('effective_name_box');
    });

    tearDown(() async {
      await HiveService.cache.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<ProviderContainer> build({
      String? cloud,
      String? email,
      String? local,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider
              .overrideWithValue(FakeAuthRepository(cloudName: cloud)),
          userEmailProvider.overrideWith((ref) async => email),
        ],
      );
      addTearDown(container.dispose);
      if (local != null) {
        await HiveService.cache.put(displayNameHiveKey, local);
      }
      return container;
    }

    test('nama lokal lebih diutamakan', () async {
      final c = await build(
        cloud: 'Cloud Name',
        email: 'budi@mail.com',
        local: 'Local Name',
      );
      expect(await c.read(effectiveDisplayNameProvider.future), 'Local Name');
    });

    test('nama cloud dipakai bila tidak ada lokal, lalu disalin ke Hive',
        () async {
      final c = await build(cloud: 'Cloud Name', email: 'budi@mail.com');
      expect(await c.read(effectiveDisplayNameProvider.future), 'Cloud Name');
      // Disalin sekali ke Hive.
      expect(HiveService.cache.get(displayNameHiveKey), 'Cloud Name');
    });

    test('nama email dipakai bila tidak ada lokal maupun cloud', () async {
      final c = await build(email: 'budi.santoso@mail.com');
      expect(await c.read(effectiveDisplayNameProvider.future), 'budi santoso');
    });

    test("fallback 'Profil saya' bila semua kosong", () async {
      final c = await build();
      expect(await c.read(effectiveDisplayNameProvider.future), 'Profil saya');
    });
  });

  group('ProfileHeader widget', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sgt_header_widget');
      Hive.init(dir.path);
      HiveService.cache = await Hive.openBox<String>('header_widget_box');
    });

    tearDown(() async {
      await HiveService.cache.clear();
    });

    tearDownAll(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Widget wrap(WidgetTester tester, {ThemeData? theme, double scale = 1.0}) {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          userEmailProvider.overrideWith((ref) async => 'budi@mail.com'),
          favoriteClubProvider.overrideWithValue(null),
          clubCrestProvider.overrideWithValue(const <String, String>{}),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: ProfileHeader(
                email: const AsyncData('budi@mail.com'),
                photoPath: null,
                onChoosePhoto: () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('menampilkan nama yang tersimpan', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          userEmailProvider.overrideWith((ref) async => 'budi@mail.com'),
          favoriteClubProvider.overrideWithValue(null),
          clubCrestProvider.overrideWithValue(const <String, String>{}),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ProfileHeader(
              email: const AsyncData('budi@mail.com'),
              photoPath: null,
              onChoosePhoto: () {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Belum ada nama lokal -> memakai nama email.
      expect(find.text('budi'), findsOneWidget);
    });

    testWidgets(
        'dialog menolak "a" lalu menerima "Budi" dan memperbarui header',
        (tester) async {
      await tester.pumpWidget(wrap(tester));
      await tester.pumpAndSettle();

      // Buka dialog ubah nama.
      await tester.tap(find.text('budi'));
      await tester.pumpAndSettle();
      expect(find.text('Ubah nama'), findsOneWidget);

      // 'a' tidak valid -> tombol Simpan nonaktif.
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(find.text('Nama minimal 2 karakter'), findsOneWidget);
      final simpan = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Simpan'),
      );
      expect(simpan.onPressed, isNull);

      // 'Budi' valid -> tombol Simpan aktif.
      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Simpan'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Simpan'))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Simpan'));
      // Penulisan Hive nyata tidak selesai di zone fakeAsync; jalankan sebentar
      // di event loop asli agar future set() tuntas dan dialog tertutup.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('Ubah nama'), findsNothing);
      expect(find.text('Nama diperbarui'), findsOneWidget);
      expect(find.text('Budi'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        '320dp + textScaler 1.3 tanpa overflow (${brightness.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            wrap(
              tester,
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              scale: 1.3,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
