import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../football/providers/football_providers.dart';
import 'widgets/cards_teaser.dart';
import 'widgets/home_hero.dart';
import 'widgets/home_stats.dart';
import 'widgets/quick_actions.dart';
import 'widgets/upcoming_matches.dart';

export 'feature_menu_tab.dart';
export 'menu_groups.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(footballRefreshProvider)(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeHero(),
                  SizedBox(height: AppSpacing.xl),
                  QuickActions(),
                  SizedBox(height: AppSpacing.xl),
                  HomeStats(),
                  SizedBox(height: AppSpacing.xl),
                  UpcomingMatches(),
                  SizedBox(height: AppSpacing.xl),
                  CardsTeaser(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
