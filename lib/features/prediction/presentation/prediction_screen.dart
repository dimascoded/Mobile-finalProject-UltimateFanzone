import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_state.dart';
import '../../football/data/football_repository.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/prediction_repository.dart';
import '../providers/prediction_provider.dart';

class PredictionScreen extends ConsumerWidget {
  const PredictionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(predictionPointsProvider);
    final pending = ref.watch(unsettledPredictionsProvider);
    final mine = ref.watch(predictionsProvider);

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
            for (final e in pending)
              _SettleTile(match: e.match, prediction: e.prediction),
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
          const _UpcomingPicker(),
          if (mine.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Tebakan tersimpan',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in mine)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text('${p.homeScore}-${p.awayScore}'),
                subtitle: Text(
                    'match #${p.matchId} • commit ${p.commit.substring(0, 12)}...'),
              ),
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
            'Skor resmi ${m.homeScore}-${m.awayScore} - buka salt untuk dapat poin'),
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
          child: const Text('Buka'),
        ),
      ),
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
  FootballMatch? _match;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(matchesProvider).valueOrNull;
    final matches = snapshot?.data ?? const <FootballMatch>[];
    final isSample = snapshot?.source == DataSource.sample;
    final now = DateTime.now().toUtc();
    // R3: laga POSTPONED/CANCELLED tidak punya skor resmi, jadi tidak bisa
    // diprediksi.
    final upcoming = matches
        .where((m) =>
            !m.isFinished && !isCancelledMatch(m) && m.kickoffUtc.isAfter(now))
        .toList()
      ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));

    if (isSample) {
      return const EmptyState(
        icon: Icons.science_outlined,
        title: 'Prediksi dinonaktifkan',
        message: 'Jadwal yang dipakai masih data contoh. Set FOOTBALL_API_KEY '
            'agar prediksi memakai jadwal sungguhan.',
      );
    }

    if (upcoming.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy,
        title: 'Tidak ada laga mendatang',
        message: 'Prediksi hanya bisa dibuat sebelum kickoff.',
      );
    }

    final selected = _match ?? upcoming.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<FootballMatch>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Laga', border: OutlineInputBorder()),
          items: [
            for (final m in upcoming)
              DropdownMenuItem<FootballMatch>(
                value: m,
                child: Text('${m.homeShort} vs ${m.awayShort}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _match = v),
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
              onPressed: value < 9 ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
