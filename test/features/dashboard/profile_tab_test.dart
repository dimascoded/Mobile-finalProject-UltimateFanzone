import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/auth/providers/auth_provider.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/profile_tab.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/providers/card_collection_provider.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';

PlClub club(String key, String name, String tla) => PlClub(
      key: key,
      name: name,
      shortName: name,
      tla: tla,
      city: 'Kota',
      stadium: 'Stadion $name',
      lat: 0,
      lng: 0,
      color: 0xFFEF0107,
      aliases: [name],
    );

final _clubs = <PlClub>[
  club('arsenal', 'Arsenal', 'ARS'),
  club('chelsea', 'Chelsea', 'CHE'),
];

/// Override murni nilai: tidak menyentuh jaringan maupun berkas, tetapi Hive
/// tetap diinisialisasi di [setUpAll] supaya provider yang membaca cache
/// (foto profil, biometrik, pengingat, waktu sync terakhir) memakai nilai
/// bawaan alih-alih melempar.
List<Override> _overrides() => [
      userEmailProvider.overrideWith((ref) async => 'budi.santoso@mail.com'),
      favoriteClubProvider.overrideWithValue(null),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      clubsProvider.overrideWith((ref) async => _clubs),
      stampsProvider.overrideWithValue(const <Block>[]),
      ownedClubsProvider.overrideWithValue(const <String>{}),
    ];

Widget _app(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1.0,
}) =>
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: const Scaffold(body: ProfileTab()),
        ),
      ),
    );

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_profile_tab');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('profile_tab_box');
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('menampilkan header, statistik, dan semua bagian pengaturan',
      (tester) async {
    await tester.pumpWidget(_app(tester));
    await tester.pumpAndSettle();

    expect(find.text('budi santoso'), findsOneWidget);
    expect(find.text('budi.santoso@mail.com'), findsOneWidget);

    expect(find.text('Stempel'), findsOneWidget);
    expect(find.text('Kartu'), findsOneWidget);
    expect(find.text('Pencapaian'), findsOneWidget);

    for (final section in const [
      'Aktivitas',
      'Keamanan',
      'Notifikasi',
      'Data',
      'Tentang',
      'Akun',
    ]) {
      expect(find.text(section), findsOneWidget, reason: 'bagian $section');
    }

    for (final tile in const [
      'Paspor Suporter',
      'Koleksi Kartu',
      'Biometrik',
      'Pengingat Kickoff',
      'Cadangan ke Cloud',
      'Kesan & Pesan',
      'Keluar',
    ]) {
      expect(find.text(tile), findsOneWidget, reason: 'tile $tile');
    }
  });

  testWidgets('menekan statistik Stempel membuka Paspor Suporter',
      (tester) async {
    await tester.pumpWidget(_app(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stempel'));
    await tester.pumpAndSettle();

    expect(find.text('Pilih tim favorit dulu'), findsOneWidget);
  });

  testWidgets('menekan statistik Kartu membuka Koleksi Kartu', (tester) async {
    await tester.pumpWidget(_app(tester));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kartu'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Main Adu Penalti'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '320dp + textScaler 1.3 tanpa overflow (${brightness.name})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _app(
            tester,
            theme:
                brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
            textScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
