import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/core/theme/app_tokens.dart';
import 'package:ultimate_fanzone/core/ui/app_card.dart';
import 'package:ultimate_fanzone/core/ui/pill_badge.dart';
import 'package:ultimate_fanzone/core/ui/scrim_image.dart';
import 'package:ultimate_fanzone/core/ui/section_header.dart';

void main() {
  const longIndo = 'Malam laga penuh semangat dan sorak sorai suporter setia';

  double luminance(Color c) {
    double r = c.r;
    double g = c.g;
    double b = c.b;
    double toLinear(double v) {
      if (v <= 0.03928) {
        return v / 12.92;
      }
      return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    r = toLinear(r);
    g = toLinear(g);
    b = toLinear(b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  double contrastRatio(Color fg, Color bg) {
    final l1 = luminance(fg);
    final l2 = luminance(bg);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  testWidgets('light and dark themes build; assert WCAG contrast >= 4.5',
      (tester) async {
    // Light
    final light = AppTheme.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: light,
        home: const SizedBox.shrink(),
      ),
    );
    final csLight = light.colorScheme;
    expect(contrastRatio(csLight.onPrimary, csLight.primary) >= 4.5, isTrue);
    expect(
        contrastRatio(csLight.onSecondary, csLight.secondary) >= 4.5, isTrue);
    expect(contrastRatio(csLight.onSurface, csLight.surface) >= 4.5, isTrue);
    // textMuted/surface
    final fzLight = light.extension<FanzoneColors>()!;
    expect(contrastRatio(fzLight.textMuted, csLight.surface) >= 4.5, isTrue);

    // Dark
    final dark = AppTheme.dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: dark,
        home: const SizedBox.shrink(),
      ),
    );
    final csDark = dark.colorScheme;
    expect(contrastRatio(csDark.onPrimary, csDark.primary) >= 4.5, isTrue);
    expect(contrastRatio(csDark.onSecondary, csDark.secondary) >= 4.5, isTrue);
    expect(contrastRatio(csDark.onSurface, csDark.surface) >= 4.5, isTrue);
    final fzDark = dark.extension<FanzoneColors>()!;
    expect(contrastRatio(fzDark.textMuted, csDark.surface) >= 4.5, isTrue);
  });

  testWidgets(
      'ScrimImage with non-existent asset renders fallback with no exception',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home:
            const ScrimImage(assetPath: 'assets/images/non_existent_xyz.webp'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('widgets render with no overflow at width 320 and textScaler 1.3',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SectionHeader(title: longIndo),
                SizedBox(height: 8),
                PillBadge(label: longIndo),
                SizedBox(height: 8),
                AppCard(child: Text(longIndo)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}
