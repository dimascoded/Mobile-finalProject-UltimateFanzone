import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_card.dart';
import '../../../../core/ui/section_header.dart';
import '../../../../core/utils/time_utils.dart';
import '../../../football/data/models.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/presentation/match_center_screen.dart';
import '../../../football/providers/football_providers.dart';

/// Daftar horizontal laga mendatang (maksimal 5), disaring ke tim favorit bila
/// sudah dipilih. Laga yang sedang tampil di hero dilewati.
class UpcomingMatches extends ConsumerWidget {
  const UpcomingMatches({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(matchesProvider).valueOrNull?.data;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final club = ref.watch(favoriteClubProvider);
    final heroId = ref.watch(nextMatchProvider).valueOrNull?.id;
    final crests = ref.watch(clubCrestProvider);

    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final list = data
        .where((m) => !m.isFinished && m.kickoffUtc.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

    var filtered = list;
    if (club != null) {
      filtered = list.where((m) => m.involves(club) && m.id != heroId).toList();
    } else if (heroId != null) {
      filtered = list.where((m) => m.id != heroId).toList();
    }
    if (filtered.isEmpty) return const SizedBox.shrink();

    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final height = 120.0 * textScale;

    void open() => Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MatchCenterScreen()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Laga berikutnya',
          actionLabel: 'Lihat semua',
          onAction: open,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filtered.length > 5 ? 5 : filtered.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => SizedBox(
              width: 220,
              child: _MatchCard(
                match: filtered[index],
                crests: crests,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MatchCenterScreen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.crests,
    required this.onTap,
  });

  final FootballMatch match;
  final Map<String, String> crests;
  final VoidCallback onTap;

  String? _crest(String? tla) => tla == null ? null : crests[tla.toUpperCase()];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wib = TimeUtils.wib(match.kickoffUtc);

    Widget teamRow(String name, String? tla) => Row(
          children: [
            ClubCrest(
              crestUrl: _crest(tla),
              tla: tla ?? name,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        );

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${TimeUtils.formatDate(wib)} • ${TimeUtils.formatHm(wib)} WIB',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          teamRow(match.homeShort, match.homeTla),
          const SizedBox(height: AppSpacing.xs),
          teamRow(match.awayShort, match.awayTla),
        ],
      ),
    );
  }
}
