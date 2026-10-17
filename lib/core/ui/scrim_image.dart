import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'pitch_pattern.dart';

class ScrimImage extends StatelessWidget {
  const ScrimImage({
    super.key,
    required this.assetPath,
    this.child,
    this.height,
    this.borderRadius = AppRadius.lg,
    this.fallbackColors,
    this.scrim = 0.6,
    this.showPitchPattern = false,
  });

  final String assetPath;
  final Widget? child;
  final double? height;
  final double borderRadius;
  final List<Color>? fallbackColors;
  final double scrim;
  final bool showPitchPattern;

  @override
  Widget build(BuildContext context) {
    final fz = context.fz;
    final fallback = fallbackColors ??
        [
          fz.heroGradientStart,
          fz.heroGradientEnd,
        ];
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final width = MediaQuery.of(context).size.width;

    final image = Image.asset(
      assetPath,
      fit: BoxFit.cover,
      cacheWidth: (width * devicePixelRatio).round(),
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fallback,
            ),
          ),
        );
      },
    );

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        image,
        // Bottom-heavy scrim
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: scrim),
              ],
            ),
          ),
        ),
        if (showPitchPattern) const PitchPattern(),
        if (child != null) child!,
      ],
    );

    if (height != null) {
      content = SizedBox(height: height, child: content);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: content,
    );
  }
}
