import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/time_utils.dart';
import '../providers/football_providers.dart';
import 'club_crest.dart';
import 'kickoff_times.dart';
import 'team_picker_screen.dart';

/// Kartu Home: tim favorit + laga berikutnya + countdown + jam di 4 zona waktu.
class FavoriteTeamCard extends ConsumerWidget {
  const FavoriteTeamCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    final next = ref.watch(nextMatchProvider);
    final now = ref.watch(tickProvider).valueOrNull ?? DateTime.now();
    void pick() => Navigator.push(
        context, MaterialPageRoute(builder: (_) => const TeamPickerScreen()));

    if (club == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.sports_soccer, size: 36),
          title: const Text('Pilih tim favorit'),
          subtitle: const Text(
              'Jadwal, pengingat, dan fitur lain menyesuaikan timmu'),
          trailing: FilledButton(onPressed: pick, child: const Text('Pilih')),
        ),
      );
    }

    final bg = club.colorValue;
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
              child: ClubCrest(
                crestUrl: ref.watch(clubCrestProvider)[club.tla.toUpperCase()],
                tla: club.tla,
                color: bg,
                size: 40,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(club.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                    Text('${club.stadium} • ${club.city}',
                        style: TextStyle(color: fg.withAlpha(217))),
                  ]),
            ),
            IconButton(onPressed: pick, icon: Icon(Icons.edit, color: fg)),
          ]),
          const Divider(),
          next.when(
            data: (m) {
              if (m == null) {
                return Text('Tidak ada laga mendatang.',
                    style: TextStyle(color: fg));
              }
              final home = club.isTeam(m.homeName, m.homeTla);
              final opponent = home ? m.awayShort : m.homeShort;
              final remaining = m.kickoffUtc.difference(now.toUtc());
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Laga berikutnya (${home ? 'kandang' : 'tandang'})',
                        style:
                            TextStyle(color: fg.withAlpha(217), fontSize: 12)),
                    Text('vs $opponent',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    KickoffTimes(utc: m.kickoffUtc, light: fg == Colors.white),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.timer, size: 18, color: fg),
                      const SizedBox(width: 6),
                      Text(TimeUtils.formatCountdown(remaining),
                          style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (isDiniHari(m.kickoffUtc)) ...[
                        const SizedBox(width: 12),
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.nightlight, size: 14),
                          label:
                              Text("Dini hari", style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ]),
                  ]);
            },
            loading: () => const LinearProgressIndicator(),
            error: (e, _) =>
                Text('Gagal memuat jadwal: $e', style: TextStyle(color: fg)),
          ),
        ]),
      ),
    );
  }
}
