import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_images.dart';
import '../../../../core/ui/pill_badge.dart';
import '../../../../core/ui/scrim_image.dart';
import '../../../../core/utils/time_utils.dart';
import '../../../football/data/models.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/presentation/kickoff_times.dart';
import '../../../football/presentation/team_picker_screen.dart';
import '../../../football/providers/football_providers.dart';
import '../../../prediction/presentation/prediction_screen.dart';

// STRUKTUR UI — HomeHero
// Ukuran: widget di dalam ScrimImage (tinggi 260 * textScale) dengan Stack
// dan Padding; konten club memakai SingleChildScrollView, tanpa batas lebar
// [1] Latar hero — ScrimImage dengan gradien warna klub sebagai fallback
// [2] Baris identitas klub — crest, nama klub, stadion dan kota, tombol ganti tim
// [3] Blok laga berikutnya — badge المنزل/tandang, nama lawan, KickoffTimes, hitung mundur, tombol Prediksi
// [4] Status jadwal — state loading (spinner), error (coba lagi), atau "Belum ada laga mendatang"
// [5] _EmptyHero — pesan "Pilih tim favoritmu" plus tombol pilih tim
// Tabel/kolom: tanpa tabel; daftar kartu satu kolom
// Sumber data: favoriteClubProvider, nextMatchProvider, tickProvider,
// clubCrestProvider, matchesProvider

/// Hero Home "Malam Laga": tim favorit, laga berikutnya, dan pintasan prediksi.
///
/// Semua teks berada di atas scrim gelap supaya tetap terbaca walau foto header
/// belum tersedia (ScrimImage otomatis jatuh ke gradien).
class HomeHero extends ConsumerWidget {
  const HomeHero({super.key});

  /// Warna klub digelapkan ~35% untuk latar gradien yang lebih pekat.
  static Color _darken(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * 0.65).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fz = context.fz;
    final theme = Theme.of(context);
    final club = ref.watch(favoriteClubProvider);
    final next = ref.watch(nextMatchProvider);
    final now = ref.watch(tickProvider).valueOrNull ?? DateTime.now();
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final height = 260.0 * textScale;
    final match = next.valueOrNull;

    void go(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    final String label;
    if (club == null) {
      label = 'Pilih tim favoritmu';
    } else if (match == null) {
      label = 'Tim favorit ${club.name}. Belum ada laga mendatang';
    } else {
      final wib = TimeUtils.wib(match.kickoffUtc);
      final opponent = club.isTeam(match.homeName, match.homeTla)
          ? match.awayShort
          : match.homeShort;
      label = 'Laga berikutnya ${club.name} vs $opponent, '
          '${TimeUtils.formatDate(wib)} ${TimeUtils.formatHm(wib)} WIB';
    }

    return Semantics(
      container: true,
      label: label,
      child: ScrimImage(
        assetPath: AppImages.heroMalamLaga,
        height: height,
        scrim: 0.75,
        showPitchPattern: true,
        fallbackColors: club == null
            ? null
            : [_darken(club.colorValue), fz.heroGradientEnd],
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (club != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      club.colorValue.withValues(alpha: 0.45),
                      club.colorValue.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: club == null
                  ? _EmptyHero(onPick: () => go(const TeamPickerScreen()))
                  : _clubContent(context, ref, theme, club, next, match, now,
                      fz.accent, go),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clubContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    PlClub club,
    AsyncValue<FootballMatch?> next,
    FootballMatch? match,
    DateTime now,
    Color accent,
    void Function(Widget) go,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClubCrest(
                  crestUrl:
                      ref.watch(clubCrestProvider)[club.tla.toUpperCase()],
                  tla: club.tla,
                  color: club.colorValue,
                  size: 40,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      club.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    Text(
                      '${club.stadium} · ${club.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => go(const TeamPickerScreen()),
                tooltip: 'Ganti tim favorit',
                icon: const Icon(Icons.edit),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          next.when(
            data: (m) {
              if (m == null) {
                return Text(
                  'Belum ada laga mendatang',
                  style:
                      theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                );
              }
              final isHome = club.isTeam(m.homeName, m.homeTla);
              final opponent = isHome ? m.awayShort : m.homeShort;
              final remaining = m.kickoffUtc.difference(now.toUtc());
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PillBadge(
                    label:
                        'Laga berikutnya · ${isHome ? 'kandang' : 'tandang'}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'vs $opponent',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: KickoffTimes(utc: match!.kickoffUtc, light: true),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer, size: 18, color: accent),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              TimeUtils.formatCountdown(remaining),
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(color: accent),
                            ),
                          ),
                        ],
                      ),
                      if (isDiniHari(match.kickoffUtc))
                        const PillBadge(
                          label: 'Dini hari',
                          tone: PillTone.accent,
                        ),
                      FilledButton(
                        onPressed: () => go(const PredictionScreen()),
                        child: const Text('Prediksi'),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Jadwal belum bisa dimuat',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(matchesProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pilih tim favoritmu',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Jadwal, pengingat, dan fitur lain menyesuaikan timmu',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: onPick,
              child: const Text('Pilih tim'),
            ),
          ],
        ),
      ),
    );
  }
}
