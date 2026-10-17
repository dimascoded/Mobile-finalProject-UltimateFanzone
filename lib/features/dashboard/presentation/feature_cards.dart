import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/pill_badge.dart';
import 'menu_groups.dart';

Widget _featureIcon(BuildContext context, IconData icon) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [
          scheme.primary,
          Color.lerp(scheme.primary, context.fz.accent, 0.5)!,
        ],
      ),
    ),
    child: Icon(icon, color: scheme.onPrimary, size: 24),
  );
}

Widget _semantics(MenuItem item, Widget child) => Semantics(
      button: true,
      label: '${item.label}. ${item.description}',
      excludeSemantics: true,
      child: child,
    );

void _open(BuildContext context, MenuItem item) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => item.page));

/// Kartu fitur utama berbentuk baris penuh.
class FeaturedFeatureCard extends StatelessWidget {
  const FeaturedFeatureCard({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _semantics(
      item,
      AppCard(
        onTap: () => _open(context, item),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            _featureIcon(context, item.icon),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (item.badge != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        PillBadge(label: item.badge!, tone: PillTone.accent),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: context.fz.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, color: context.fz.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Kartu fitur untuk grid.
class FeatureCard extends StatelessWidget {
  const FeatureCard({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _semantics(
      item,
      AppCard(
        onTap: () => _open(context, item),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _featureIcon(context, item.icon),
                if (item.badge != null)
                  Flexible(
                    child: PillBadge(label: item.badge!, tone: PillTone.accent),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              item.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Text(
                item.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: context.fz.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
