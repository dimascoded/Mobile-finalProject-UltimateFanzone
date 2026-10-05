import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../football/data/football_repository.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../data/prediction_repository.dart';
import '../providers/prediction_provider.dart';

/// Berapa-manyakismatch yang ditampilkan sekaligus (UI3).
const kMaxUpcomingMatches = 20;

/// Laga mendatang milik tim favorit saja, dibatasi [kMaxUpcomingMatches].
final favoriteUpcomingMatchesProvider =
    Provider<List<FootballMatch>>((ref) {
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final fav = ref.watch(favoriteClubProvider);
  return upcomingMatches(matches, fav);
});

/// Laga mendatang tanpa filter tim, dibatasi juga.
final allUpcomingMatchesProvider = Provider<List<FootballMatch>>((ref) {
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  return upcomingMatches(matches, null);
});

/// Laga yang masih bisa diprediksi: belum selesai, belum dibatalkan, kickoff
/// masih di depan. Tanpa ini, daftar bisa tumbuh tak terbatas dan memuat laga
/// yang memang tidak bisa ditebak.
List<FootballMatch> upcomingMatches(List<FootballMatch> matches, PlClub? fav) {
  final now = DateTime.now().toUtc();
  final list = matches
      .where((m) =>
          !m.isFinished &&
          !isCancelledMatch(m) &&
          m.kickoffUtc.isAfter(now) &&
          (fav == null || m.involves(fav)))
      .toList()
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
  return list.take(kMaxUpcomingMatches).toList();
}

/// Riwayat tebakan: poin diambil dari blok result, bukan dari nilai lokal.
final predictionHistoryProvider =
    Provider<List<({FootballMatch? match, Prediction prediction, int? points})>>((ref) {
  final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final chain = ref.watch(chainProvider);
  final predictions = ref.watch(predictionsProvider);

  final resultsByMatch = <int, int>{
    for (final b in chain.where((b) => b.type == Prediction.blockTypeResult))
      if (b.data['match'] is num && b.data['points'] is num)
        (b.data['match'] as num).toInt(): (b.data['points'] as num).toInt(),
  };

  final out = <({FootballMatch? match, Prediction prediction, int? points})>[];
  for (final p in predictions) {
    FootballMatch? m;
    for (final candidate in matches) {
      if (candidate.id == p.matchId) {
        m = candidate;
        break;
      }
    }
    out.add((match: m, prediction: p, points: resultsByMatch[p.matchId]));
  }
  out.sort((a, b) => b.prediction.createdAt.compareTo(a.prediction.createdAt));
  return out;
});

/// Layar Prediksi Skor.
class PredictionScreen extends ConsumerWidget {
  const PredictionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(predictionPointsProvider);
    final pending = ref.watch(unsettledPredictionsProvider);
    final history = ref.watch(predictionHistoryProvider);
    final snapshot = ref.watch(matchesProvider).valueOrNull;
    final isSample = snapshot?.source == DataSource.sample;

    return Scaffold(
      appBar: AppBar(title: const Text('Prediksi Skor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.stars_outlined),
              title: Text('$points poin'),
              subtitle: const Text('Hanya poin, tanpa odds atau uang'),
            ),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Siap dicek', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final e in pending) _SettleTile(match: e.match, prediction: e.prediction),
          ],
          const SizedBox(height: 16),
          Text('Pilih skor sebelum kickoff',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Skor dikunci dengan hash SHA-256 dan tidak bisa diubah setelah kickoff.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (isSample)
            const EmptyState(
              icon: Icons.science_outlined,
              title: 'Prediksi dinonaktifkan',
              message: 'Jadwal yang dipakai masih data contoh. Set FOOTBALL_API_KEY '
                  'agar prediksi memakai jadwal sungguhan.',
            )
          else
            const _UpcomingPicker(),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Tebakan tersimpan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final h in history) _HistoryTile(entry: h),
          ],
        ],
      ),
    );
  }
}

class _SettleTile extends ConsumerStatefulWidget {
  const _SettleTile({required this.match, required this.prediction});

  final FootballMatch match;
  final Prediction prediction;

  @override
  ConsumerState<_SettleTile> createState() => _SettleTileState();
}

class _SettleTileState extends ConsumerState<_SettleTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: Text('${m.homeShort} vs ${m.awayShort} selesai'),
        subtitle: Text(
            'Skor resmi ${m.homeScore}-${m.awayScore} - cek hasil untuk dapat poin'),
        trailing: FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await ref
                      .read(settleActionProvider)
                      .settle(m, widget.prediction);
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        r == null
                            ? 'Gagal membuka prediksi'
                            : r.valid
                                ? 'Prediksi sah! +${r.points} poin'
                                : 'Prediksi tidak sah, 0 poin',
                      ),
                    ),
                  );
                },
          child: const Text('Cek hasil'),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final ({FootballMatch? match, Prediction prediction, int? points}) entry;

  @override
  Widget build(BuildContext context) {
    final p = entry.prediction;
    final m = entry.match;
    final wib = TimeUtils.wib(p.createdAt);
    final title = m == null
        ? 'Laga #${p.matchId}'
        : '${m.homeShort} vs ${m.awayShort}';
    final status = entry.points != null
        ? 'Selesai • +${entry.points} poin'
        : (m == null
            ? 'Menunggu jadwal'
            : (m.isFinished
                ? 'Belum dicek'
                : 'Menunggu kickoff ${TimeUtils.formatHm(TimeUtils.wib(m.kickoffUtc))} WIB'));

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(entry.points != null ? Icons.workspace_premium : Icons.lock_outline),
      title: Text('$title  ${p.homeScore}-${p.awayScore}'),
      subtitle: Text('${TimeUtils.formatDate(wib)}, ${TimeUtils.formatHm(wib)} WIB • $status'),
    );
  }
}

class _UpcomingPicker extends ConsumerStatefulWidget {
  const _UpcomingPicker();

  @override
  ConsumerState<_UpcomingPicker> createState() => _UpcomingPickerState();
}

class _UpcomingPickerState extends ConsumerState<_UpcomingPicker> {
  int _home = 1;
  int _away = 0;

  /// Simpan ID, bukan objek FootballMatch (UI3). Objeknya datang dari FutureProvider
  /// yang bisa dibangun ulang, sehingga nilai lama tidak lagi termasuk list dan
  /// DropdownButton akan assertion.
  int? _selectedMatchId;
  bool _allMatches = false;

  @override
  Widget build(BuildContext context) {
    final fav = ref.watch(favoriteClubProvider);
    final matches = _allMatches
        ? ref.watch(allUpcomingMatchesProvider)
        : ref.watch(favoriteUpcomingMatchesProvider);

    // Laga yang tidak bisa diprediksi (mis. sudah lewat kickoff karena daftar
    // lama masih tampil) dibuang, lalu pilihan yang tidak berlaku dikembalikan.
    final selectable = matches;
    final current = _selectedMatchId != null &&
            selectable.any((m) => m.id == _selectedMatchId)
        ? _selectedMatchId
        : (selectable.isEmpty ? null : selectable.first.id);

    if (selectable.isEmpty) {
      final message = fav == null || !_allMatches
          ? 'Belum ada laga mendatang untuk tim favoritmu. Pilih tim di Home atau tekan "Semua laga".'
          : 'Tidak ada laga mendatang. Prediksi hanya bisa dibuat sebelum kickoff.';
      return EmptyState(
        icon: Icons.event_busy,
        title: 'Tidak ada laga untuk ditebak',
        message: message,
      );
    }

    final selected = selectable.firstWhere((m) => m.id == current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fav != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _allMatches = !_allMatches),
              icon: Icon(_allMatches ? Icons.star : Icons.star_border),
              label: Text(_allMatches ? 'Semua laga' : '${fav.name} saja'),
            ),
          ),
        DropdownButtonFormField<int>(
          key: ValueKey(selected.id),
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Laga', border: OutlineInputBorder()),
          items: [
            for (final m in selectable)
              DropdownMenuItem<int>(
                value: m.id,
                child: Text(
                  '${m.homeShort} vs ${m.awayShort} • ${_wibLabel(m.kickoffUtc)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _selectedMatchId = v),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Stepper(
              label: selected.homeShort,
              value: _home,
              onChanged: (v) => setState(() => _home = v),
            ),
            Text('vs', style: Theme.of(context).textTheme.titleMedium),
            _Stepper(
              label: selected.awayShort,
              value: _away,
              onChanged: (v) => setState(() => _away = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final r = await ref.read(predictionActionProvider).commit(
                    match: selected,
                    homeScore: _home,
                    awayScore: _away,
                  );
              messenger.showSnackBar(
                SnackBar(
                  content: Text(r.alreadyCommitted
                      ? 'Sudah ada prediksi untuk laga ini'
                      : 'Prediksi $_home-$_away dikunci'),
                ),
              );
            } catch (e) {
              messenger.showSnackBar(SnackBar(
                  content: Text(e.toString().replaceFirst('Exception: ', ''))));
            }
          },
          icon: const Icon(Icons.lock),
          label: const Text('Kunci prediksi'),
        ),
      ],
    );
  }

  /// "Sen, 03 Nov • 23:30 WIB" supaya user tidak salah baca zona waktu.
  static String _wibLabel(DateTime utc) {
    final wib = TimeUtils.wib(utc);
    return '${TimeUtils.formatDate(wib)}, ${TimeUtils.formatHm(wib)} WIB';
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              tooltip: 'Kurangi skor $label',
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 48,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
            ),
            IconButton.filledTonal(
              tooltip: 'Tambah skor $label',
              onPressed: value < 9 ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
