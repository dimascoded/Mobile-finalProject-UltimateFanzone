import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/pill_badge.dart';
import '../../../core/ui/scrim_image.dart';
import 'feature_cards.dart';
import 'menu_groups.dart';

export 'feature_cards.dart';
export 'menu_groups.dart';

String _headerImage(FeatureSection section) => switch (section) {
      FeatureSection.matches => AppImages.headerLaga,
      FeatureSection.activities => AppImages.headerSeru,
      FeatureSection.tools => AppImages.headerAlat,
    };

Color _fallbackStart(BuildContext context, FeatureSection section) {
  final scheme = Theme.of(context).colorScheme;
  final accent = context.fz.accent;
  return switch (section) {
    FeatureSection.matches => scheme.primary,
    FeatureSection.activities => Color.lerp(scheme.primary, accent, 0.5)!,
    FeatureSection.tools => Color.lerp(scheme.primary, scheme.secondary, 0.5)!,
  };
}

/// Tab menu dengan header bergambar dan kartu fitur.
class FeatureMenuTab extends StatelessWidget {
  const FeatureMenuTab({required this.section, super.key});

  final FeatureSection section;

  @override
  Widget build(BuildContext context) {
    final group = menuGroups[section]!;
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final isWide = width >= 600;
    final columns = width >= 900
        ? 4
        : isWide
            ? 3
            : 2;
    final items =
        isWide ? group.items : group.items.skip(1).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeaderBanner(section: section, group: group),
                const SizedBox(height: AppSpacing.lg),
                if (!isWide) ...[
                  FeaturedFeatureCard(item: group.items.first),
                  const SizedBox(height: AppSpacing.lg),
                ],
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 176 * scale,
                  ),
                  itemBuilder: (context, i) => FeatureCard(item: items[i]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Header bergambar untuk satu bagian menu.
class SectionHeaderBanner extends StatelessWidget {
  const SectionHeaderBanner({
    super.key,
    required this.section,
    required this.group,
  });

  final FeatureSection section;
  final MenuGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    return ScrimImage(
      assetPath: _headerImage(section),
      height: 170 * scale,
      borderRadius: AppRadius.xl,
      scrim: 0.7,
      showPitchPattern: true,
      fallbackColors: [
        _fallbackStart(context, section),
        context.fz.heroGradientEnd,
      ],
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                group.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              PillBadge(label: '${group.items.length} fitur'),
            ],
          ),
        ),
      ),
    );
  }
}
