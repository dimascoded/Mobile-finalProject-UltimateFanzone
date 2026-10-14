import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/football_repository.dart';
import '../data/models.dart';
import '../providers/football_providers.dart';
import '../providers/kickoff_reminder_provider.dart';
import 'club_crest.dart';
import 'data_source_banner.dart';
import 'kickoff_times.dart';

class MatchCenterScreen extends ConsumerWidget {
  const MatchCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Match Center'),
          actions: [
            IconButton(
              tooltip: 'Atur pengingat kickoff',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => _setReminders(context, ref),
            ),
            IconButton(
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(footballRefreshProvider)(),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Jadwal'),
            Tab(text: 'Klasemen'),
            Tab(text: 'Top Skor'),
          ]),
        ),
        body: const TabBarView(
            children: [_FixturesTab(), _StandingsTab(), _ScorersTab()]),
      ),
    );
  }

  Future<void> _setReminders(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = ref.read(matchesProvider).valueOrNull?.source;
    if (source == DataSource.sample) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Pengingat dinonaktifkan: data contoh, bukan jadwal sebenarnya.'),
      ));
      return;
    }
    final fav = ref.read(favoriteClubProvider);
    if (fav == null) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Pilih tim favorit dulu agar pengingat bisa dijadwalkan.')));
      return;
    }
    final n = await scheduleRemindersForUpcoming(ref);
    final message = n > 0
        ? '$n pengingat kickoff untuk ${fav.name} dijadwalkan '
            '(30 menit sebelum main, maks $maxKickoffReminders laga)'
        : 'Tidak ada laga ${fav.name} mendatang untuk dijadwalkan';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

// ---------------- Jadwal ----------------
class _FixturesTab extends ConsumerWidget {
  const _FixturesTab();

  static const _labels = {
    MatchFilter.upcoming: 'Mendatang',
    MatchFilter.favorite: 'Tim favorit',
    MatchFilter.finished: 'Selesai',
    MatchFilter.all: 'Semua',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(filteredMatchesProvider);
    final filter = ref.watch(matchFilterProvider);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          onChanged: (v) => ref.read(matchQueryProvider.notifier).state = v,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), labelText: 'Cari tim'),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          for (final f in MatchFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(_labels[f]!),
                selected: filter == f,
                onSelected: (_) =>
                    ref.read(matchFilterProvider.notifier).state = f,
              ),
            ),
        ]),
      ),
      Expanded(
        child: state.when(
          data: (r) => Column(children: [
            DataSourceBanner(source: r.source, fetchedAt: r.fetchedAt),
            Expanded(
              child: r.data.isEmpty
                  ? const EmptyState(
                      icon: Icons.sports_soccer,
                      title: 'Tidak ada pertandingan',
                      message: 'Ubah filter atau kata kunci pencarian.')
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: r.data.length,
                      itemBuilder: (_, i) => _MatchTile(match: r.data[i]),
                    ),
            ),
          ]),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center),
          )),
        ),
      ),
    ]);
  }
}

class _MatchTile extends ConsumerWidget {
  const _MatchTile({required this.match});
  final FootballMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoriteClubProvider);
    final homeFav = fav != null && fav.isTeam(match.homeName, match.homeTla);
    final awayFav = fav != null && fav.isTeam(match.awayName, match.awayTla);
    FontWeight w(bool b) => b ? FontWeight.bold : FontWeight.normal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(match.matchday == null ? '' : 'Pekan ${match.matchday}',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            if (match.isOngoing)
              const Chip(
                  label: Text('Berlangsung'),
                  visualDensity: VisualDensity.compact),
            if (match.isFinished)
              const Chip(
                  label: Text('Selesai'), visualDensity: VisualDensity.compact),
            if (!match.isFinished && isDiniHari(match.kickoffUtc))
              const Chip(
                avatar: Icon(Icons.nightlight, size: 14),
                label: Text('Dini hari'),
                visualDensity: VisualDensity.compact,
              ),
          ]),
          Row(children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(match.homeShort,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: w(homeFav), fontSize: 16)),
                  ),
                  const SizedBox(width: 6),
                  ClubCrest(
                    crestUrl: match.homeCrest,
                    tla: match.homeTla ?? '',
                    color: homeFav ? fav.colorValue : null,
                    size: 28,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                match.hasScore
                    ? '${match.homeScore} - ${match.awayScore}'
                    : 'vs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  ClubCrest(
                    crestUrl: match.awayCrest,
                    tla: match.awayTla ?? '',
                    color: awayFav ? fav.colorValue : null,
                    size: 28,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(match.awayShort,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: w(awayFav), fontSize: 16)),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 8),
          KickoffTimes(utc: match.kickoffUtc),
        ]),
      ),
    );
  }
}

// ---------------- Klasemen ----------------
class _StandingsTab extends ConsumerWidget {
  const _StandingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(standingsProvider);
    final fav = ref.watch(favoriteClubProvider);

    Widget cell(String t, double w,
            {bool bold = false, TextAlign a = TextAlign.center}) =>
        SizedBox(
          width: w,
          child: Text(t,
              textAlign: a,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        );

    return state.when(
      data: (r) => Column(children: [
        DataSourceBanner(source: r.source, fetchedAt: r.fetchedAt),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            cell('#', 28, bold: true),
            Expanded(child: cell('Tim', 0, bold: true, a: TextAlign.left)),
            cell('M', 30, bold: true),
            cell('M', 30, bold: true),
            cell('S', 30, bold: true),
            cell('K', 30, bold: true),
            cell('SG', 36, bold: true),
            cell('Poin', 40, bold: true),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: r.data.isEmpty
              ? const EmptyState(
                  icon: Icons.table_rows, title: 'Klasemen belum tersedia')
              : ListView.builder(
                  itemCount: r.data.length,
                  itemBuilder: (_, i) {
                    final row = r.data[i];
                    final mine =
                        fav != null && fav.isTeam(row.teamName, row.tla);
                    return Container(
                      color: mine ? fav.colorValue.withAlpha(46) : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(children: [
                        cell('${row.position}', 28),
                        ClubCrest(
                          crestUrl: row.crest,
                          tla: row.tla ?? '',
                          color: mine ? fav.colorValue : null,
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                            child: cell(row.teamShort, 0,
                                a: TextAlign.left, bold: mine)),
                        cell('${row.played}', 30),
                        cell('${row.won}', 30),
                        cell('${row.draw}', 30),
                        cell('${row.lost}', 30),
                        cell('${row.goalDiff}', 36),
                        cell('${row.points}', 40, bold: true),
                      ]),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('M=Main  M=Menang  S=Seri  K=Kalah  SG=Selisih gol',
              style: TextStyle(fontSize: 11)),
        ),
      ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}

// ---------------- Top skor ----------------
class _ScorersTab extends ConsumerWidget {
  const _ScorersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scorersProvider);
    return state.when(
      data: (r) => Column(children: [
        DataSourceBanner(source: r.source, fetchedAt: r.fetchedAt),
        Expanded(
          child: r.data.isEmpty
              ? const EmptyState(
                  icon: Icons.emoji_events,
                  title: 'Belum ada data pencetak gol')
              : ListView.builder(
                  itemCount: r.data.length,
                  itemBuilder: (_, i) {
                    final s = r.data[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(s.player),
                      subtitle: Row(children: [
                        ClubCrest(
                          crestUrl: s.crest,
                          tla: s.tla ?? '',
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(s.teamShort),
                      ]),
                      trailing: Text('${s.goals} gol',
                          style: Theme.of(context).textTheme.titleMedium),
                    );
                  },
                ),
        ),
      ]),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}
