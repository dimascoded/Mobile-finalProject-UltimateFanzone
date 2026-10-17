import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/section_header.dart';
import '../../../../core/ui/stat_tile.dart';
import '../../../away_day/presentation/away_day_screen.dart';
import '../../../away_day/providers/away_day_providers.dart';
import '../../../football/providers/football_providers.dart';
import '../../../gamification/presentation/card_collection_screen.dart';
import '../../../gamification/presentation/passport_screen.dart';
import '../../../gamification/providers/card_collection_provider.dart';
import '../../../gamification/providers/gamification_providers.dart';

/// Ringkasan angka privat: pengeluaran away day, stempel, dan kartu klub.
class HomeStats extends ConsumerWidget {
  const HomeStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    final totals = ref.watch(awayDayTotalsProvider);
    final budget = ref.watch(awayDayBudgetProvider);
    final chain = ref.watch(stampsProvider);
    final cards = ref.watch(cardCollectionProvider);
    final stamps = club == null
        ? chain.length
        : chain.where((b) => b.data['club'] == club.key).length;

    final budgetDetail =
        budget > 0 ? 'dari Rp ${budget.round()}' : 'belum ada anggaran';
    final stampDetail = club == null ? 'semua stadion' : 'di ${club.name}';

    void go(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Ringkasan'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Away Day',
                value: 'Rp ${totals.idr.round()}',
                detail: budgetDetail,
                onTap: () => go(const AwayDayScreen()),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: 'Stempel',
                value: '$stamps',
                detail: stampDetail,
                onTap: () => go(const PassportScreen()),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: 'Kartu Klub',
                value: '${cards.length}',
                detail: 'terkumpul',
                onTap: () => go(const CardCollectionScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
