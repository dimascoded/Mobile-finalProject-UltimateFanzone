import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
}

class AppRadius {
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 28.0;
  static const double pill = 999.0;
}

@immutable
class FanzoneColors extends ThemeExtension<FanzoneColors> {
  const FanzoneColors({
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.surfaceHigh,
    required this.textMuted,
    required this.heroGradientStart,
    required this.heroGradientEnd,
  });

  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color surfaceHigh;
  final Color textMuted;
  final Color heroGradientStart;
  final Color heroGradientEnd;

  @override
  FanzoneColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? surfaceHigh,
    Color? textMuted,
    Color? heroGradientStart,
    Color? heroGradientEnd,
  }) {
    return FanzoneColors(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      textMuted: textMuted ?? this.textMuted,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
    );
  }

  @override
  FanzoneColors lerp(ThemeExtension<FanzoneColors>? other, double t) {
    if (other is! FanzoneColors) {
      return this;
    }
    return FanzoneColors(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      heroGradientStart:
          Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
    );
  }
}

extension FanzoneContext on BuildContext {
  FanzoneColors get fz {
    final ext = Theme.of(this).extension<FanzoneColors>();
    if (ext == null) {
      throw Exception('FanzoneColors extension not found in current theme');
    }
    return ext;
  }
}
