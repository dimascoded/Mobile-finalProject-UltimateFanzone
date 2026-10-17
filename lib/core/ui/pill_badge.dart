import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

enum PillTone { neutral, accent, success }

class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = PillTone.neutral,
  });

  final String label;
  final Widget? icon;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fz = context.fz;
    Color bg;
    Color fg;
    switch (tone) {
      case PillTone.accent:
        bg = fz.accent;
        fg = fz.onAccent;
        break;
      case PillTone.success:
        bg = scheme.primary;
        fg = scheme.onPrimary;
        break;
      case PillTone.neutral:
        bg = scheme.surfaceContainerHigh;
        fg = scheme.onSurface;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outline, width: 1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
