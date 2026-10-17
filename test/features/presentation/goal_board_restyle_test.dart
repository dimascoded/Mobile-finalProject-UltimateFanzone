import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/core/ui/app_images.dart';
import 'package:ultimate_fanzone/core/ui/scrim_image.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/game_screen.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/data/penalty_rules.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/presentation/penalty_screen.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/providers/penalty_provider.dart';

class _MissingGoalAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == AppImages.gameGoal) {
      return Future<ByteData>.error(FlutterError('Missing test image'));
    }
    return rootBundle.load(key);
  }
}

class _FixedReflexNotifier extends ReflexNotifier {
  _FixedReflexNotifier(super.ref) {
    state = const ReflexState(running: true, zone: KickZone.topLeft);
  }
}

void main() {
  late Directory tempDirectory;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('goal_board_test');
    Hive.init(tempDirectory.path);
    HiveService.cache = await Hive.openBox<String>('goal_board_test');
    await HiveService.cache.put('permission_rationale', '["sensors"]');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDirectory.existsSync()) {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  const zoneLabels = [
    'Kiri atas',
    'Tengah atas',
    'Kanan atas',
    'Kiri bawah',
    'Tengah bawah',
    'Kanan bawah',
  ];

  for (final brightness in Brightness.values) {
    testWidgets(
        'penalty goal board fallback and tap at 320dp '
        '(${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const PenaltyScreen(), brightness));
      await tester.pumpAndSettle();

      for (final label in zoneLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(_fallbackFinder, findsOneWidget);
      expect(find.byType(ScrimImage), findsOneWidget);
      _expectGoalImageVisibleThroughCells(tester, zoneLabels);
      await tester.tap(find.text('Kiri atas'));
      await tester.pump();
      expect(find.text('Ayun'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'reflex goal grid fallback and tap at 320dp '
        '(${brightness.name})', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const GameScreen(), brightness));
      await tester.pumpAndSettle();

      for (final label in zoneLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(_fallbackFinder, findsOneWidget);
      await tester.tap(find.text('Kiri atas'));
      await tester.pump();
      expect(find.text('10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app(Widget screen, Brightness brightness) => ProviderScope(
      overrides: [
        penaltyProvider.overrideWith((ref) => PenaltyNotifier(ref)),
        reflexProvider.overrideWith((ref) => _FixedReflexNotifier(ref)),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => DefaultAssetBundle(
          bundle: _MissingGoalAssetBundle(),
          child: child!,
        ),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: screen,
        ),
      ),
    );

void _expectGoalImageVisibleThroughCells(
  WidgetTester tester,
  List<String> zoneLabels,
) {
  expect(find.byType(ScrimImage), findsOneWidget);

  for (final label in zoneLabels) {
    final containers = find.ancestor(
      of: find.text(label),
      matching: find.byType(Container),
    );
    final ancestors = tester.widgetList<Container>(containers);
    expect(
      ancestors,
      isNotEmpty,
      reason: 'Zone "$label" should sit inside the goal board container',
    );
    for (final container in ancestors) {
      final decoration = container.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        expect(
          decoration.color!.a,
          lessThan(1.0),
          reason: 'Every widget between the goal image and zone "$label" must '
              'be translucent so the image shows through, but found an opaque '
              'fill',
        );
      }
    }
  }
}

final _fallbackFinder = find.byWidgetPredicate(
  (widget) {
    if (widget is! Container || widget.decoration is! BoxDecoration) {
      return false;
    }
    final gradient = (widget.decoration! as BoxDecoration).gradient;
    return gradient is LinearGradient &&
        gradient.colors.first != Colors.transparent &&
        gradient.colors.last == Colors.black;
  },
);
