import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/rates_provider.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../football/providers/football_providers.dart';
import '../data/away_day_repository.dart';
import '../providers/away_day_providers.dart';

/// Pemisah ribuan tanpa menambah dependensi intl.
String _group(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String _rp(double v) => 'Rp${_group(v.round())}';
String _gbp(double v) => '\u00A3${v.toStringAsFixed(2)}';

const _catLabel = {
  AwayDayCategory.tiket: 'Tiket',
  AwayDayCategory.hotel: 'Hotel',
  AwayDayCategory.transport: 'Transportasi',
  AwayDayCategory.merchandise: 'Merchandise',
  AwayDayCategory.makanan: 'Makanan',
  AwayDayCategory.lainnya: 'Lainnya',
};

const _catIcon = {
  AwayDayCategory.tiket: Icons.confirmation_number_outlined,
  AwayDayCategory.hotel: Icons.hotel_outlined,
  AwayDayCategory.transport: Icons.directions_transit_outlined,
  AwayDayCategory.merchandise: Icons.shopping_bag_outlined,
  AwayDayCategory.makanan: Icons.restaurant_outlined,
  AwayDayCategory.lainnya: Icons.more_horiz,
};

class AwayDayScreen extends ConsumerWidget {
  const AwayDayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(awayDayTotalsProvider);
    final budget = ref.watch(awayDayBudgetProvider);
    final items = ref.watch(awayDayFilteredProvider);
    final clock = ref.watch(worldClockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Away Day')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Catat'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _Summary(totals: totals, budget: budget),
          const SizedBox(height: 12),
          _WorldClock(clock: clock),
          const SizedBox(height: 12),
          const _Filters(),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Belum ada pengeluaran',
              message: 'Tekan Catat untuk menambah pengeluaran Away Day.',
            )
          else
            for (final e in items) _Tile(expense: e),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.totals, required this.budget});

  final ({double idr, double gbp}) totals;
  final double budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pct = budget > 0 ? (totals.idr / budget * 100).clamp(0.0, 100.0) : 0.0;
    final over = budget > 0 && totals.idr > budget;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total pengeluaran', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              _rp(totals.idr),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: over ? scheme.error : scheme.primary,
                  ),
            ),
            Text(_gbp(totals.gbp), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (budget > 0) ...[
              LinearProgressIndicator(
                value: pct / 100,
                color: over ? scheme.error : scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 6),
              Text(
                over
                    ? 'Melebihi anggaran ${_rp(totals.idr - budget)}'
                    : 'Sisa anggaran ${_rp(budget - totals.idr)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: over ? scheme.error : null,
                    ),
              ),
            ] else
              TextButton.icon(
                onPressed: () => _editBudget(context, ref),
                icon: const Icon(Icons.savings_outlined, size: 18),
                label: const Text('Atur anggaran'),
              ),
            if (budget > 0)
              TextButton.icon(
                onPressed: () => _editBudget(context, ref),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Ubah anggaran'),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorldClock extends StatelessWidget {
  const _WorldClock({required this.clock});

  final AsyncValue<Map<String, DateTime>> clock;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, size: 18),
                const SizedBox(width: 8),
                Text('Jam dunia', style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 12),
            clock.when(
              loading: () => const SizedBox(height: 40, child: LinearProgressIndicator()),
              error: (e, _) => Text('Gagal: $e'),
              data: (m) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final e in m.entries)
                    Column(
                      children: [
                        Text(e.key, style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text(
                          TimeUtils.formatHm(e.value),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(awayDayCategoryFilterProvider);
    final favOnly = ref.watch(awayDayFavOnlyProvider);
    final hasFav = ref.watch(favoriteKeyProvider) != null;

    return Column(
      children: [
        TextField(
          onChanged: (v) => ref.read(awayDayQueryProvider.notifier).state = v,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: 'Cari pengeluaran',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('Semua'),
                selected: cat == null,
                onSelected: (_) =>
                    ref.read(awayDayCategoryFilterProvider.notifier).state = null,
              ),
              const SizedBox(width: 8),
              if (hasFav) ...[
                FilterChip(
                  avatar: const Icon(Icons.star, size: 18),
                  label: const Text('Tim favorit'),
                  selected: favOnly,
                  onSelected: (v) =>
                      ref.read(awayDayFavOnlyProvider.notifier).state = v,
                ),
                const SizedBox(width: 8),
              ],
              for (final c in AwayDayCategory.values) ...[
                FilterChip(
                  avatar: Icon(_catIcon[c], size: 18),
                  label: Text(_catLabel[c]!),
                  selected: cat == c,
                  onSelected: (v) => ref
                      .read(awayDayCategoryFilterProvider.notifier)
                      .state = v ? c : null,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.expense});

  final AwayDayExpense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(clubsProvider).valueOrNull?.where((c) => c.key == expense.clubKey).firstOrNull;

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => ref.read(awayDayProvider.notifier).remove(expense.id),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
                club?.colorValue ?? Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              _catIcon[expense.category],
              size: 20,
              color: club == null ? null : Colors.white,
            ),
          ),
          title: Text(expense.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              _catLabel[expense.category],
              if (club != null) club.name,
              TimeUtils.formatDate(expense.date),
            ].join(' \u00B7 '),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_rp(expense.amountIdr), style: Theme.of(context).textTheme.titleSmall),
              Text(_gbp(expense.amountGbp), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _editBudget(BuildContext context, WidgetRef ref) async {
  final current = ref.read(awayDayBudgetProvider);
  final ctl = TextEditingController(text: current > 0 ? current.round().toString() : '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Anggaran harian'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ),
  );
  if (saved == true) {
    await ref.read(awayDayBudgetProvider.notifier).set(double.tryParse(ctl.text) ?? 0);
  }
}

Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
  final rates = ref.read(ratesProvider).valueOrNull;
  final favKey = ref.read(favoriteKeyProvider);
  final clubs = ref.read(clubsProvider).valueOrNull ?? const [];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddForm(rates: rates, favKey: favKey, clubs: clubs),
    ),
  );
}

class _AddForm extends ConsumerStatefulWidget {
  const _AddForm({required this.rates, required this.favKey, required this.clubs});

  final Map<String, double>? rates;
  final String? favKey;
  final List clubs;

  @override
  ConsumerState<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends ConsumerState<_AddForm> {
  final _title = TextEditingController();
  final _gbp = TextEditingController();
  final _idr = TextEditingController();
  AwayDayCategory _cat = AwayDayCategory.tiket;
  String? _clubKey;
  bool _useGbp = true;

  @override
  void initState() {
    super.initState();
    _clubKey = widget.favKey;
    if (widget.rates == null) _useGbp = false;
    _gbp.addListener(_syncFromGbp);
    _idr.addListener(_syncFromIdr);
  }

  @override
  void dispose() {
    _title.dispose();
    _gbp.dispose();
    _idr.dispose();
    super.dispose();
  }

  void _syncFromGbp() {
    if (!_useGbp) return;
    final v = double.tryParse(_gbp.text);
    final idr = v == null ? null : gbpToIdr(v, widget.rates);
    _idr.text = idr == null ? '' : idr.round().toString();
  }

  void _syncFromIdr() {
    if (_useGbp) return;
    final v = double.tryParse(_idr.text);
    final g = v == null ? null : idrToGbp(v, widget.rates);
    _gbp.text = g == null ? '' : g.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final rates = ref.watch(ratesProvider).valueOrNull;
    final offline = rates == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Catat pengeluaran', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('GBP'), icon: Icon(Icons.attach_money)),
              ButtonSegment(value: false, label: Text('IDR'), icon: Icon(Icons.payments_outlined)),
            ],
            selected: {_useGbp},
            onSelectionChanged: offline
                ? null
                : (s) => setState(() {
                      _useGbp = s.first;
                      if (_useGbp) {
                        _syncFromIdr();
                      } else {
                        _syncFromGbp();
                      }
                    }),
          ),
          const SizedBox(height: 12),
          if (_useGbp)
            TextField(
              controller: _gbp,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Jumlah (GBP)', prefixText: '\u00A3', border: OutlineInputBorder()),
            )
          else
            TextField(
              controller: _idr,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah (IDR)', prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 8),
          Text(
            offline
                ? 'Kurs tidak tersedia. Masukkan nilai Rupiah manual.'
                : 'Kurs: 1 GBP = ${_rp(1 / rates[awayDayCurrency]!)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AwayDayCategory>(
            initialValue: _cat,
            decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
            items: [
              for (final c in AwayDayCategory.values)
                DropdownMenuItem(value: c, child: Text(_catLabel[c]!)),
            ],
            onChanged: (v) => setState(() => _cat = v ?? AwayDayCategory.lainnya),
          ),
          const SizedBox(height: 12),
          if (widget.clubs.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _clubKey,
              decoration: const InputDecoration(labelText: 'Klub', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('Umum')),
                for (final c in widget.clubs)
                  DropdownMenuItem<String>(value: c.key, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _clubKey = v),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final g = double.tryParse(_gbp.text) ?? 0;
    final i = double.tryParse(_idr.text) ?? 0;
    if (_title.text.trim().isEmpty || (g <= 0 && i <= 0)) return;
    ref.read(awayDayProvider.notifier).add(
          title: _title.text.trim(),
          amountGbp: g,
          amountIdr: i,
          category: _cat,
          clubKey: _clubKey,
        );
    Navigator.of(context).pop();
  }
}