import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/pill_badge.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../football/data/football_repository.dart';
import '../../football/data/models.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../sync/providers/sync_provider.dart';
import '../data/prediction_rank.dart';
import '../data/prediction_repository.dart';
import '../data/reveal_verifier.dart';
import '../providers/prediction_provider.dart';

/// Berapa-manyakismatch yang ditampilkan sekaligus (UI3).
const kMaxUpcomingMatches = 20;

/// Laga mendatang milik tim favorit saja, dibatasi [kMaxUpcomingMatches].
final favoriteUpcomingMatchesProvider = Provider<List<FootballMatch>>((ref) {
  final matches =
      ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  final fav = ref.watch(favoriteClubProvider);
  return upcomingMatches(matches, fav);
});

/// Laga mendatang tanpa filter tim, dibatasi juga.
final allUpcomingMatchesProvider = Provider<List<FootballMatch>>((ref) {
  final matches =
      ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
  return upcomingMatches(matches, null);
});

/// Laga yang masih bisa diprediksi: belum selesai, belum dibatalkan, kickoff
/// masih di depan. Tanpa ini, daftar bisa tumbuh tak terbatas dan memuat laga
/// yang memang tidak bisa ditebak.
List<FootballMatch> upcomingMatches(List<FootballMatch> matches, PlClub? fav) {
  final now = DateTime.now().toUtc();
  final list = matches
      .where((m) =>
          m.phaseAt(now) == MatchPhase.upcoming &&
          (fav == null || m.involves(fav)))
      .toList()
    ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
  return list.take(kMaxUpcomingMatches).toList();
}

/// Riwayat tebakan: poin diambil dari blok result, bukan dari nilai lokal.
final predictionHistoryProvider = Provider<
    List<({FootballMatch? match, Prediction prediction, int? points})>>((ref) {
  final matches =
      ref.watch(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
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

/// Dialog konfirmasi hapus prediksi. Mengembalikan true bila user menekan
/// "Hapus".
Future<bool> _confirmDeletePrediction(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: const Text(
        'Hapus prediksi ini? Poin dan kartu yang sudah kamu dapat tidak '
        'berubah, dan laga ini tidak bisa diprediksi ulang.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Konfirmasi lalu hapus satu prediksi. Poin/kartu yang sudah didapat tetap;
/// yang hilang hanya baris prediksi (dan baris cloud-nya saat sync berikutnya).
Future<void> _deletePrediction(
  BuildContext context,
  WidgetRef ref, {
  required int matchId,
  required DateTime? kickoffUtc,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await _confirmDeletePrediction(context)) return;
  final removed = await ref.read(predictionsProvider.notifier).remove(
        matchId,
        kickoffUtc: kickoffUtc,
        nowUtc: DateTime.now().toUtc(),
      );
  messenger.showSnackBar(SnackBar(
    content: Text(removed ? 'Prediksi dihapus' : 'Prediksi tidak bisa dihapus'),
  ));
}

/// Layar Prediksi Skor.
class PredictionScreen extends ConsumerWidget {
  const PredictionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(predictionPointsProvider);
    final rank = rankFor(points);
    final next = nextRank(points);
    final pending = ref.watch(unsettledPredictionsProvider);
    final history = ref.watch(predictionHistoryProvider);
    final snapshot = ref.watch(matchesProvider).valueOrNull;
    final isSample = snapshot?.source == DataSource.sample;

    return Scaffold(
      appBar: AppBar(title: const Text('Prediksi Skor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PillBadge(label: rank.name, tone: PillTone.accent),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '$points poin',
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LinearProgressIndicator(value: progressToNext(points)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      next == null
                          ? 'Peringkat tertinggi'
                          : '${next.min - points} poin lagi menuju ${next.name}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Setiap naik peringkat kamu dapat 1 Kartu Klub',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: const Text('Cara dapat poin'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          'Tebakan pas: 3 poin',
                          'Meleset 1 gol: 2 poin',
                          'Meleset 2 gol: 1 poin',
                          'Arah hasil benar (menang/seri/kalah): +1 poin',
                          'Maksimal 4 poin per laga',
                          'Tanpa taruhan atau uang',
                        ]
                            .map((line) => Padding(
                                  padding:
                                      const EdgeInsets.only(top: AppSpacing.xs),
                                  child: Text(line),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                const SectionHeader(title: 'Siap dicek'),
                const SizedBox(height: AppSpacing.xs),
                for (final e in pending)
                  _SettleTile(match: e.match, prediction: e.prediction),
              ],
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader(title: 'Pilih skor sebelum kickoff'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Prediksi dikunci dan tidak bisa diubah setelah kickoff.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              if (isSample)
                const EmptyState(
                  icon: Icons.science_outlined,
                  title: 'Prediksi dinonaktifkan',
                  message:
                      'Jadwal yang dipakai masih data contoh. Set FOOTBALL_API_KEY '
                      'agar prediksi memakai jadwal sungguhan.',
                )
              else
                const _UpcomingPicker(),
              if (history.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Tebakan tersimpan'),
                const SizedBox(height: AppSpacing.sm),
                for (final h in history) _HistoryTile(entry: h),
              ],
            ],
          ),
        ),
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
  bool _syncing = false;
  bool _missingCommit = false;
  bool _saltLost = false;
  String? _debug;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _missingCommit = false;
      _saltLost = false;
      _debug = null;
    });
    var failed = false;
    var hashMismatch = false;
    String? message;
    String? debug;
    try {
      final r = await ref
          .read(settleActionProvider)
          .settleDetailed(widget.match, widget.prediction);
      final settled = r.settled;
      if (settled != null) {
        message = settled.rankUp != null
            ? 'Naik peringkat: ${settled.rankUp!.name}! Kamu dapat 1 Kartu Klub.'
            : settled.valid
                ? 'Prediksi sah! +${settled.points} poin'
                : 'Prediksi tidak sah, 0 poin';
      } else {
        failed = true;
        message = r.reason ?? 'Gagal membuka prediksi';
        debug = r.debug;
        hashMismatch = r.reason == kHashMismatchReason;
        debugPrint('Cek hasil gagal: $message${debug == null ? '' : ' | $debug'}');
      }
    } catch (e) {
      failed = true;
      message = e.toString().replaceFirst('Exception: ', '');
      debugPrint('Cek hasil error: $message');
    } finally {
      // Selalu lepas status sibuk, termasuk saat minting/penulisan blok gagal.
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() {
      _debug = debug;
      _missingCommit = failed && message == kNoCommitReason;
      _saltLost = failed && hashMismatch;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sync() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      await ref.read(syncProvider.notifier).run();
      messenger.showSnackBar(
          const SnackBar(content: Text('Sinkronisasi selesai, coba cek lagi.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _delete() => _deletePrediction(
        context,
        ref,
        matchId: widget.match.id,
        kickoffUtc: widget.match.kickoffUtc,
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Row(children: [
              ClubCrest(crestUrl: m.homeCrest, tla: m.homeTla ?? '', size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${m.homeShort} vs ${m.awayShort} selesai',
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              ClubCrest(crestUrl: m.awayCrest, tla: m.awayTla ?? '', size: 20),
            ]),
            subtitle: Text(
                'Skor resmi ${m.homeScore}-${m.awayScore} - cek hasil untuk dapat poin'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_saltLost)
                  FilledButton(
                    onPressed: _busy ? null : _check,
                    child: const Text('Cek hasil'),
                  ),
                IconButton(
                  tooltip: 'Hapus prediksi',
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          if (_missingCommit)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bukti commit tidak ditemukan di rantai perangkat ini; '
                    'coba Sinkronkan lalu cek lagi',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _syncing ? null : _sync,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sinkronkan'),
                    ),
                  ),
                ],
              ),
            ),
          if (_saltLost || _debug != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_saltLost)
                    Text(
                      'Salt tebakan hilang, prediksi ini tidak bisa dibuka',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_debug != null) ...[
                    if (_saltLost) const SizedBox(height: AppSpacing.xs),
                    Text(_debug!, style: Theme.of(context).textTheme.labelSmall),
                  ],
                  if (_saltLost) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Hapus prediksi'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});

  final ({FootballMatch? match, Prediction prediction, int? points}) entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = entry.match;
    final phase = m?.phaseAt(DateTime.now().toUtc());
    final canDelete = m != null && m.kickoffUtc.isBefore(DateTime.now().toUtc());
    final theme = Theme.of(context);
    final p = entry.prediction;
    final wib = TimeUtils.wib(p.createdAt);
    final title =
        m == null ? 'Laga #${p.matchId}' : '${m.homeShort} vs ${m.awayShort}';
    final status = entry.points != null
        ? 'Selesai • +${entry.points} poin'
        : (m == null
            ? 'Menunggu jadwal'
            : switch (phase!) {
                MatchPhase.upcoming =>
                  'Menunggu kickoff ${TimeUtils.formatHm(TimeUtils.wib(m.kickoffUtc))} WIB',
                MatchPhase.live => 'Sedang berlangsung',
                MatchPhase.awaitingResult => 'Menunggu hasil resmi',
                MatchPhase.finished => 'Belum dicek',
                MatchPhase.cancelled => 'Laga diundur/dibatalkan',
              });
    final tone = entry.points != null
        ? (entry.points! > 0 ? PillTone.success : PillTone.neutral)
        : (phase == MatchPhase.finished || phase == MatchPhase.awaitingResult
            ? PillTone.accent
            : PillTone.neutral);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (m != null) ...[
              ClubCrest(crestUrl: m.homeCrest, tla: m.homeTla ?? '', size: 20),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                '$title  ${p.homeScore}-${p.awayScore}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (m != null) ...[
              const SizedBox(width: AppSpacing.xs),
              ClubCrest(crestUrl: m.awayCrest, tla: m.awayTla ?? '', size: 20),
            ],
          ]),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillBadge(label: status, tone: tone),
              Text(
                '${TimeUtils.formatDate(wib)}, ${TimeUtils.formatHm(wib)} WIB',
                style: theme.textTheme.bodySmall,
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Hapus prediksi',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deletePrediction(
                    context,
                    ref,
                    matchId: p.matchId,
                    kickoffUtc: m.kickoffUtc,
                  ),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
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
                child: Row(children: [
                  ClubCrest(
                      crestUrl: m.homeCrest, tla: m.homeTla ?? '', size: 20),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${m.homeShort} vs ${m.awayShort} • ${_wibLabel(m.kickoffUtc)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ClubCrest(
                      crestUrl: m.awayCrest, tla: m.awayTla ?? '', size: 20),
                ]),
              ),
          ],
          onChanged: (v) => setState(() => _selectedMatchId = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Stepper(
                label: selected.homeShort,
                crestUrl: selected.homeCrest,
                tla: selected.homeTla ?? '',
                value: _home,
                onChanged: (v) => setState(() => _home = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text('vs', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: _Stepper(
                label: selected.awayShort,
                crestUrl: selected.awayCrest,
                tla: selected.awayTla ?? '',
                value: _away,
                onChanged: (v) => setState(() => _away = v),
              ),
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
                      ? 'Prediksi sudah dikunci untuk laga ini'
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
      {required this.label,
      required this.value,
      required this.onChanged,
      this.crestUrl,
      this.tla = ''});

  final String label;
  final String? crestUrl;
  final String tla;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (crestUrl != null) ...[
          ClubCrest(crestUrl: crestUrl, tla: tla, size: 32),
          const SizedBox(height: 4),
        ],
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
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
        ),
      ],
    );
  }
}
