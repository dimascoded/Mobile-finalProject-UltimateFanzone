import 'package:flutter/material.dart';

import '../../away_day/presentation/away_day_screen.dart';
import '../../football/presentation/match_center_screen.dart';
import '../../gamification/presentation/game_screen.dart';
import '../../gamification/presentation/passport_screen.dart';
import '../../lens/presentation/lens_screen.dart';
import '../../penalty_shootout/presentation/penalty_screen.dart';
import '../../prediction/presentation/prediction_screen.dart';
import '../../pundit/presentation/pundit_screen.dart';
import '../../stadium_pointer/presentation/stadium_pointer_screen.dart';

/// Tab menu utama Dashboard: Laga, Seru, dan Alat.
enum FeatureSection { matches, activities, tools }

/// Satu fitur di dalam sebuah grup menu.
typedef MenuItem = ({
  String label,
  String description,
  IconData icon,
  Widget page,
  String? badge,
});

// STRUKTUR UI — menuGroups (registry menu, tanpa komposisi UI)
// Ukuran: bukan widget; konstanta registry <FeatureSection, MenuGroup>.
// [1] FeatureSection — enum tiga tab: matches, activities, tools
// [2] MenuItem      — tuple: label, description, icon, page, badge
// [3] MenuGroup     — judul, deskripsi, ikon, dan daftar item tiap tab
// Tabel/kolom: tanpa tabel; tiap grup memuat tiga item MenuItem.
// Sumber data: tanpa provider; konstanta statis yang dirender lewat
//              FeatureMenuTab, FeatureCard, dan FeaturedFeatureCard.
/// Sekelompok fitur yang ditampilkan pada satu tab menu.
class MenuGroup {
  const MenuGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.items,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<MenuItem> items;
}

const menuGroups = <FeatureSection, MenuGroup>{
  FeatureSection.matches: MenuGroup(
    title: 'Pertandingan',
    description: 'Ikuti laga, susun prediksi, dan temukan arah ke stadion.',
    icon: Icons.sports_soccer,
    items: [
      (
        label: 'Match Center',
        description: 'Jadwal dan hasil pertandingan',
        icon: Icons.sports_soccer,
        page: MatchCenterScreen(),
        badge: null,
      ),
      (
        label: 'Prediksi Skor',
        description: 'Buat prediksi sebelum kickoff',
        icon: Icons.scoreboard_outlined,
        page: PredictionScreen(),
        badge: null,
      ),
      (
        label: 'Kompas Stadion',
        description: 'Peta dan arah ke stadion pilihan',
        icon: Icons.explore,
        page: StadiumPointerScreen(),
        badge: null,
      ),
    ],
  ),
  FeatureSection.activities: MenuGroup(
    title: 'Seru-seruan',
    description: 'Kumpulkan pencapaian dan uji keterampilanmu.',
    icon: Icons.sports_esports,
    items: [
      (
        label: 'Paspor Suporter',
        description: 'Stamp stadion dan pencapaian',
        icon: Icons.approval,
        page: PassportScreen(),
        badge: null,
      ),
      (
        label: 'Penalty Shootout',
        description: 'Tantang kiper dalam adu penalti',
        icon: Icons.sports_gymnastics,
        page: PenaltyScreen(),
        badge: null,
      ),
      (
        label: 'Refleks Kiper',
        description: 'Tangkis bola secepat mungkin',
        icon: Icons.sports_esports,
        page: GameScreen(),
        badge: null,
      ),
    ],
  ),
  FeatureSection.tools: MenuGroup(
    title: 'Alat Bantu',
    description: 'Asisten pintar, pemindai harga, dan rencana away day.',
    icon: Icons.widgets,
    items: [
      (
        label: 'Pundit AI',
        description: 'Analisis dan obrolan seputar klub',
        icon: Icons.auto_awesome,
        page: PunditScreen(),
        badge: 'AI',
      ),
      (
        label: 'Scan Struk & Tiket',
        description: 'Pindai harga dari foto',
        icon: Icons.document_scanner,
        page: LensScreen(),
        badge: 'Kamera',
      ),
      (
        label: 'Away Day',
        description: 'Atur anggaran perjalanan tandang',
        icon: Icons.currency_exchange,
        page: AwayDayScreen(),
        badge: null,
      ),
    ],
  ),
};
