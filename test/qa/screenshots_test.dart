// Golden screenshot QA. Tag `screenshots` dikecualikan dari `flutter test`
// biasa lewat dart_test.yaml, jadi berkas ini hanya jalan saat diminta:
//
//   flutter test test/qa/screenshots_test.dart --update-goldens --tags screenshots
//
// PNG hasil ditulis ke build/qa_screens/. Font asli (Barlow Condensed + Inter)
// dimuat lebih dulu supaya golden memakai tipografi yang sama dengan aplikasi;
// gambar sengaja tidak tersedia sehingga setiap `ScrimImage` tampil fallback.
@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/auth/presentation/login_screen.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/home_tab.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/profile_tab.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/card_collection_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/game_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/passport_screen.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/presentation/penalty_screen.dart';

import 'qa_harness.dart';

class _Shot {
  const _Shot(
    this.name,
    this.build, {
    this.favorite = false,
    this.populated = false,
  });

  final String name;
  final Widget Function() build;
  final bool favorite;
  final bool populated;
}

const String _goldenDir = '../../build/qa_screens';

final List<_Shot> _shots = <_Shot>[
  _Shot('login', () => const LoginScreen()),
  _Shot('home_no_favorite', () => const Scaffold(body: HomeTab())),
  _Shot('home_with_favorite', () => const Scaffold(body: HomeTab()),
      favorite: true),
  _Shot(
      'menu_laga',
      () => const Scaffold(
          body: FeatureMenuTab(section: FeatureSection.matches))),
  _Shot(
      'menu_seru',
      () => const Scaffold(
          body: FeatureMenuTab(section: FeatureSection.activities))),
  _Shot(
      'menu_alat',
      () =>
          const Scaffold(body: FeatureMenuTab(section: FeatureSection.tools))),
  _Shot('profile', () => const Scaffold(body: ProfileTab())),
  _Shot('passport', () => const PassportScreen(), favorite: true),
  _Shot('card_collection_empty', () => const CardCollectionScreen()),
  _Shot('card_collection_filled', () => const CardCollectionScreen(),
      populated: true),
  _Shot('penalty_board', () => const PenaltyScreen()),
  _Shot('reflex_grid', () => const GameScreen()),
];

Future<void> _loadFonts() async {
  final condensed = FontLoader('BarlowCondensed')
    ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
  await condensed.load();

  final inter = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
  await inter.load();
}

void main() {
  // Golden hanya ditulis/dibandingkan lewat `--update-goldens`. Tanpa flag itu
  // berkas ini mendaftarkan nol uji, sehingga `flutter test` biasa (atau run
  // dengan `--exclude-tags screenshots`) tidak menyentuh golden sama sekali.
  if (!autoUpdateGoldenFiles) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUpAll(() async {
    installQaFakeSensors();
    dir = await initQaHive('shots');
    await _loadFonts();
  });

  tearDownAll(() async {
    await disposeQaHive(dir);
  });

  Directory('build/qa_screens').createSync(recursive: true);

  for (final shot in _shots) {
    for (final brightness in Brightness.values) {
      testWidgets('golden: ${shot.name} (${brightness.name})', (tester) async {
        await pumpScreen(
          tester,
          shot.build(),
          size: const Size(360, 800),
          textScale: 1.0,
          brightness: brightness,
          overrides: qaOverrides(
            favorite: shot.favorite,
            populated: shot.populated,
          ),
        );
        await settleQa(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('$_goldenDir/${shot.name}_${brightness.name}.png'),
        );
      });
    }
  }
}
