// Matriks visual QA: setiap layar dipompa pada kombinasi ukuran, skala teks,
// dan tema. Kegagalan TIDAK menghentikan loop: semuanya dikumpulkan lalu
// dilaporkan sebagai tabel supaya sekali jalan ketahuan semua masalah.
//
// Grup kedua pada textScale 2.0 bersifat informasi saja (peringatan dicetak,
// tidak menggagalkan uji) karena skala ekstrem memang di luar target dukungan.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/auth/presentation/login_screen.dart';
import 'package:ultimate_fanzone/features/auth/presentation/register_screen.dart';
import 'package:ultimate_fanzone/features/away_day/presentation/away_day_screen.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/feedback_screen.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/home_tab.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/profile_tab.dart';
import 'package:ultimate_fanzone/features/football/presentation/match_center_screen.dart';
import 'package:ultimate_fanzone/features/football/presentation/reminder_settings_screen.dart';
import 'package:ultimate_fanzone/features/football/presentation/team_picker_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/card_collection_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/game_screen.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/passport_screen.dart';
import 'package:ultimate_fanzone/features/lens/presentation/lens_screen.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/presentation/penalty_screen.dart';
import 'package:ultimate_fanzone/features/prediction/presentation/prediction_screen.dart';
import 'package:ultimate_fanzone/features/pundit/presentation/pundit_screen.dart';
import 'package:ultimate_fanzone/features/sos_emergency/presentation/sos_screen.dart';
import 'package:ultimate_fanzone/features/stadium_pointer/presentation/stadium_pointer_screen.dart';

import 'qa_harness.dart';

class _Case {
  const _Case(
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

const List<Size> _sizes = <Size>[
  Size(320, 640),
  Size(360, 800),
  Size(412, 915),
  Size(800, 1280),
];

const List<double> _scales = <double>[1.0, 1.3];

String _label(Size size, double scale, Brightness brightness) =>
    '${size.width.toInt()}x${size.height.toInt()} | x$scale | '
    '${brightness.name}';

final List<_Case> _cases = <_Case>[
  _Case('HomeTab', () => const Scaffold(body: HomeTab())),
  _Case('HomeTab (favorite)', () => const Scaffold(body: HomeTab()),
      favorite: true),
  _Case(
      'FeatureMenuTab.matches',
      () => const Scaffold(
          body: FeatureMenuTab(section: FeatureSection.matches))),
  _Case(
      'FeatureMenuTab.activities',
      () => const Scaffold(
          body: FeatureMenuTab(section: FeatureSection.activities))),
  _Case(
      'FeatureMenuTab.tools',
      () =>
          const Scaffold(body: FeatureMenuTab(section: FeatureSection.tools))),
  _Case('ProfileTab', () => const Scaffold(body: ProfileTab())),
  _Case('LoginScreen', () => const LoginScreen()),
  _Case('RegisterScreen', () => const RegisterScreen()),
  _Case('TeamPickerScreen', () => const TeamPickerScreen()),
  _Case('ReminderSettingsScreen', () => const ReminderSettingsScreen()),
  _Case('FeedbackScreen', () => const FeedbackScreen()),
  _Case('SosScreen', () => const SosScreen()),
  _Case('MatchCenterScreen', () => const MatchCenterScreen()),
  _Case('PredictionScreen', () => const PredictionScreen()),
  _Case('PunditScreen', () => const PunditScreen()),
  _Case('PassportScreen', () => const PassportScreen()),
  _Case('PassportScreen (favorite)', () => const PassportScreen(),
      favorite: true),
  _Case('CardCollectionScreen', () => const CardCollectionScreen()),
  _Case('CardCollectionScreen (filled)', () => const CardCollectionScreen(),
      populated: true),
  _Case('AwayDayScreen', () => const AwayDayScreen()),
  _Case('PenaltyScreen', () => const PenaltyScreen()),
  _Case('GameScreen', () => const GameScreen()),
  _Case('LensScreen', () => const LensScreen()),
  _Case(
    'CompassDial (sub-widget)',
    () => const Scaffold(
      body: Center(
        child: CompassDialTestWrapper(
          relativeBearing: 42,
          color: Color(0xFFEF0107),
        ),
      ),
    ),
  ),
];

Future<String?> _runCombo(
  WidgetTester tester,
  _Case screenCase,
  Size size,
  double textScale,
  Brightness brightness,
) async {
  FlutterErrorDetails? details;
  final previous = FlutterError.onError;
  FlutterError.onError = (errorDetails) {
    details ??= errorDetails;
    previous?.call(errorDetails);
  };
  try {
    await pumpScreen(
      tester,
      screenCase.build(),
      size: size,
      textScale: textScale,
      brightness: brightness,
      overrides: qaOverrides(
        favorite: screenCase.favorite,
        populated: screenCase.populated,
      ),
    );
    await settleQa(tester);
    final error = tester.takeException();
    if (error == null) return null;
    return details != null ? qaErrorSummary(details!) : qaErrorSummary(error);
  } catch (error) {
    return qaErrorSummary(error);
  } finally {
    FlutterError.onError = previous;
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    installQaFakeSensors();
    dir = await initQaHive('matrix');
  });

  tearDownAll(() async {
    await disposeQaHive(dir);
  });

  for (final screenCase in _cases) {
    testWidgets('matrix: ${screenCase.name}', (tester) async {
      final failures = <String>[];
      for (final size in _sizes) {
        for (final textScale in _scales) {
          for (final brightness in Brightness.values) {
            final error = await _runCombo(
                tester, screenCase, size, textScale, brightness);
            if (error != null) {
              failures.add(
                '${screenCase.name} | ${_label(size, textScale, brightness)} | '
                '$error',
              );
            }
          }
        }
      }
      expect(
        failures,
        isEmpty,
        reason: failures.isEmpty
            ? null
            : '\nlayar | ukuran | skala | tema | error\n${failures.join('\n')}',
      );
    });
  }

  // Grup informasi: skala teks ekstrem (2.0) pada 360x800 saja. Kegagalan
  // dicetak sebagai peringatan dan tidak menggagalkan uji.
  for (final screenCase in _cases) {
    testWidgets('textScale 2.0 warnings: ${screenCase.name}', (tester) async {
      final warnings = <String>[];
      for (final brightness in Brightness.values) {
        final error = await _runCombo(
            tester, screenCase, const Size(360, 800), 2.0, brightness);
        if (error != null) {
          warnings.add(
            '${screenCase.name} | 360x800 | x2.0 | ${brightness.name} | $error',
          );
        }
      }
      for (final warning in warnings) {
        qaWarn(warning);
      }
    });
  }
}
