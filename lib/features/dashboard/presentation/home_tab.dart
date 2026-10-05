import 'package:flutter/material.dart';
import '../../pundit/presentation/pundit_screen.dart';
import '../../stadium_pointer/presentation/stadium_pointer_screen.dart';
import '../../away_day/presentation/away_day_screen.dart';
import '../../gamification/presentation/game_screen.dart';
import '../../gamification/presentation/passport_screen.dart';
import '../../lens/presentation/lens_screen.dart';
import '../../penalty_shootout/presentation/penalty_screen.dart';
import '../../prediction/presentation/prediction_screen.dart';
import '../../sos_emergency/presentation/sos_screen.dart';
import '../../football/presentation/favorite_team_card.dart';
import '../../football/presentation/match_center_screen.dart';
import 'fan_summary.dart';

/// Satu grup tombol. Dipakai supaya Home tidak terlihat seperti daftar panjang
/// tanpa arah (UI1).
class _MenuGroup {
  const _MenuGroup(this.title, this.items);

  final String title;
  final List<({String label, IconData icon, Widget page})> items;
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  static final _groups = <_MenuGroup>[
    const _MenuGroup('Pertandingan', [
      (label: 'Match Center', icon: Icons.sports_soccer, page: MatchCenterScreen()),
      (label: 'Prediksi Skor', icon: Icons.scoreboard_outlined, page: PredictionScreen()),
      (label: 'Kompas Stadion', icon: Icons.explore, page: StadiumPointerScreen()),
    ]),
    const _MenuGroup('Seru-seruan', [
      (label: 'Paspor Digital', icon: Icons.approval, page: PassportScreen()),
      (label: 'Penalty Shootout', icon: Icons.sports_gymnastics, page: PenaltyScreen()),
      (label: 'Mini Game', icon: Icons.sports_esports, page: GameScreen()),
    ]),
    const _MenuGroup('Alat Bantu', [
      (label: 'Pundit AI', icon: Icons.auto_awesome, page: PunditScreen()),
      (label: 'Lens (OCR Harga)', icon: Icons.document_scanner, page: LensScreen()),
      (label: 'Away Day', icon: Icons.currency_exchange, page: AwayDayScreen()),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Padding bawah 104 menyisakan ruang untuk tombol SOS mengambang supaya
      // kartu terakhir tidak tertutup.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      children: [
        const FavoriteTeamCard(),
        const FanSummary(),
        for (final group in _groups) ...[
          _GroupHeader(group.title),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              for (final m in group.items)
                _MenuTile(label: m.label, icon: m.icon, page: m.page),
            ],
          ),
          const SizedBox(height: 16),
        ],
        const SosCard(),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        child: Text(title, style: theme.textTheme.titleSmall),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.label, required this.icon, required this.page});

  final String label;
  final IconData icon;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen())),
        child: Semantics(
          button: true,
          label: 'SOS Darurat',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.sos, size: 36, color: Theme.of(context).colorScheme.onErrorContainer),
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
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onErrorContainer),
            ]),
          ),
        ),
      ),
    );
  }
}
