import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/home_tab.dart';

Widget _app(
    WidgetTester tester, FeatureSection section, Brightness brightness) {
  return ProviderScope(
    child: MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Scaffold(body: FeatureMenuTab(section: section)),
      ),
    ),
  );
}

void main() {
  for (final section in FeatureSection.values) {
    for (final width in const [320.0, 900.0]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          '$section @ ${width.toInt()}dp ${brightness.name}',
          (tester) async {
            tester.view.physicalSize = Size(width, 800);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_app(tester, section, brightness));
            await tester.pumpAndSettle();

            final group = menuGroups[section]!;
            expect(find.text(group.title), findsOneWidget);
            for (final item in group.items) {
              expect(find.text(item.label), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
