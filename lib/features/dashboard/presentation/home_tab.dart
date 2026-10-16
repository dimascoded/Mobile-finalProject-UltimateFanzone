import 'package:flutter/material.dart';
import '../../away_day/presentation/away_day_screen.dart';
import '../../football/presentation/favorite_team_card.dart';
import '../../football/presentation/match_center_screen.dart';
import '../../gamification/presentation/game_screen.dart';
import '../../gamification/presentation/passport_screen.dart';
import '../../lens/presentation/lens_screen.dart';
import '../../penalty_shootout/presentation/penalty_screen.dart';
import '../../prediction/presentation/prediction_screen.dart';
import '../../pundit/presentation/pundit_screen.dart';
import '../../sos_emergency/presentation/sos_screen.dart';
import '../../stadium_pointer/presentation/stadium_pointer_screen.dart';
import 'fan_summary.dart';

enum FeatureSection { matches, activities, tools }

class _MenuGroup {
  const _MenuGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.items,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<({String label, String description, IconData icon, Widget page})>
      items;
}

const _menuGroups = <FeatureSection, _MenuGroup>{
  FeatureSection.matches: _MenuGroup(
    title: 'Pertandingan',
    description: 'Ikuti laga, susun prediksi, dan temukan arah ke stadion.',
    icon: Icons.sports_soccer,
    items: [
      (
        label: 'Match Center',
        description: 'Jadwal dan hasil pertandingan',
        icon: Icons.sports_soccer,
        page: MatchCenterScreen(),
      ),
      (
        label: 'Prediksi Skor',
        description: 'Buat prediksi sebelum kickoff',
        icon: Icons.scoreboard_outlined,
        page: PredictionScreen(),
      ),
      (
        label: 'Kompas Stadion',
        description: 'Peta dan arah ke stadion pilihan',
        icon: Icons.explore,
        page: StadiumPointerScreen(),
      ),
    ],
  ),
  FeatureSection.activities: _MenuGroup(
    title: 'Seru-seruan',
    description: 'Kumpulkan pencapaian dan uji keterampilanmu.',
    icon: Icons.sports_esports,
    items: [
      (
        label: 'Paspor Suporter',
        description: 'Stamp stadion dan pencapaian',
        icon: Icons.approval,
        page: PassportScreen(),
      ),
      (
        label: 'Penalty Shootout',
        description: 'Tantang kiper dalam adu penalti',
        icon: Icons.sports_gymnastics,
        page: PenaltyScreen(),
      ),
      (
        label: 'Speed Tapper',
        description: 'Uji refleks dalam tantangan cepat',
        icon: Icons.sports_esports,
        page: GameScreen(),
      ),
    ],
  ),
  FeatureSection.tools: _MenuGroup(
    title: 'Alat Bantu',
    description: 'Asisten pintar, pemindai harga, dan rencana away day.',
    icon: Icons.widgets,
    items: [
      (
        label: 'Pundit AI',
        description: 'Analisis dan obrolan seputar klub',
        icon: Icons.auto_awesome,
        page: PunditScreen(),
      ),
      (
        label: 'Scan Struk & Tiket',
        description: 'Pindai harga dari foto',
        icon: Icons.document_scanner,
        page: LensScreen(),
      ),
      (
        label: 'Away Day',
        description: 'Atur anggaran perjalanan tandang',
        icon: Icons.currency_exchange,
        page: AwayDayScreen(),
      ),
    ],
  ),
};

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      children: const [
        FavoriteTeamCard(),
        FanSummary(),
        SosCard(),
      ],
    );
  }
}

class FeatureMenuTab extends StatelessWidget {
  const FeatureMenuTab({required this.section, super.key});

  final FeatureSection section;

  @override
  Widget build(BuildContext context) {
    final group = _menuGroups[section]!;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 4
        : width >= 600
            ? 3
            : 2;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      children: [
        _SectionBanner(group: group),
        const SizedBox(height: 20),
        Text('Fitur', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: width >= 600 ? 1.15 : 0.9,
          ),
          itemBuilder: (context, index) => _MenuTile(item: group.items[index]),
        ),
      ],
    );
  }
}

class _SectionBanner extends StatelessWidget {
  const _SectionBanner({required this.group});

  final _MenuGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(group.icon, size: 34, color: colors.onPrimaryContainer),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: textTheme.titleLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  group.description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});

  final ({String label, String description, IconData icon, Widget page}) item;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => item.page)),
        child: Semantics(
          button: true,
          label: item.label,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      item.icon,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SOS dipisah dari grid karena harus mudah dijangkau saat darurat, dan supaya
/// tombol tetap ada di Home saat tab lain terbuka.
class SosCard extends StatelessWidget {
  const SosCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SosScreen())),
        child: Semantics(
          button: true,
          label: 'SOS Darurat',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.sos,
                  size: 36,
                  color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'SOS Darurat',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ]),
          ),
        ),
      ),
    );
  }
}
