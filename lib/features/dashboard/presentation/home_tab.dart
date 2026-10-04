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

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final menus = <(String, IconData, Widget)>[
      ('Match Center', Icons.sports_soccer, const MatchCenterScreen()),
      ('Prediksi Skor', Icons.scoreboard_outlined, const PredictionScreen()),
      ('Pundit AI', Icons.auto_awesome, const PunditScreen()),
      ('Lens (OCR Harga)', Icons.document_scanner, const LensScreen()),
      ('Kompas Stadion', Icons.explore, const StadiumPointerScreen()),
      ('Away Day', Icons.currency_exchange, const AwayDayScreen()),
      ('Paspor Digital', Icons.approval, const PassportScreen()),
      ('Mini Game', Icons.sports_esports, const GameScreen()),
      ('Penalty Shootout', Icons.gps_fixed, const PenaltyScreen()),
      ('SOS Darurat', Icons.sos, const SosScreen()),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const FavoriteTeamCard(),
        const FanSummary(),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            for (final m in menus)
              Card(
                child: InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.$3)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(m.$2, size: 40),
                      const SizedBox(height: 8),
                      Text(m.$1, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}