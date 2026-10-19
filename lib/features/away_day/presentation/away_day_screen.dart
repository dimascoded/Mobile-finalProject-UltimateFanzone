import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/rates_provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../data/away_day_repository.dart';
import '../data/city_time.dart';
import '../data/currency_convert.dart';
import '../providers/away_day_providers.dart';

/// Parse angka yang diketik pengguna.
///
/// Keyboard di Indonesia sering mengirim koma sebagai pemisah desimal
/// ("45,50"), sedangkan [double.tryParse] hanya menerima titik. Karena itu koma
/// diganti dulu. String lain (mis. "1.234,56" dari format Accounting) ditolak
/// dengan pesan yang jelas daripada diam-diam jadi 0.
double? parseAmount(String raw) {
  final cleaned = raw.trim().replaceAll(' ', '');
  if (cleaned.isEmpty) return null;
  if (cleaned.contains('.')) return double.tryParse(cleaned);
  if (cleaned.contains(',')) {
    return double.tryParse(cleaned.replaceAll(',', '.'));
  }
  return double.tryParse(cleaned);
}

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

String _currencyPrefix(String currency) => switch (currency) {
      'GBP' => '\u00A3 ',
      'USD' => '\$ ',
      'EUR' => '\u20AC ',
      _ => 'Rp ',
    };

String _foreignAmount(double amount, String currency) =>
    formatMoney(amount, currency);

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
            children: [
              _Summary(totals: totals, budget: budget),
              const SizedBox(height: AppSpacing.md),
              _WorldClock(clock: clock),
              const SizedBox(height: AppSpacing.md),
              const _Filters(),
              const SizedBox(height: AppSpacing.md),
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
        ),
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
    final summary = ref.watch(awayDaySummaryProvider);
    final selectedCurrency = ref.watch(awayDaySummaryCurrencyProvider);
    final snap = ref.watch(ratesProvider).valueOrNull;
    final totalIdr = summary.totalIdr;
    final pct = budget > 0 ? (totalIdr / budget * 100).clamp(0.0, 100.0) : 0.0;
    final over = budget > 0 && totalIdr > budget;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total pengeluaran',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            formatMoney(summary.total, selectedCurrency),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: over ? scheme.error : scheme.primary,
                ),
          ),
          if (selectedCurrency != 'IDR')
            Text('\u2248 ${_rp(totalIdr)}',
                style: Theme.of(context).textTheme.bodyMedium)
          else
            Text(_gbp(totals.gbp),
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text('Tampilkan dalam',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final info in supportedCurrencies.values)
                ChoiceChip(
                  label: Text(info.code),
                  selected: selectedCurrency == info.code,
                  onSelected: (v) {
                    if (v) {
                      ref
                          .read(awayDaySummaryCurrencyProvider.notifier)
                          .set(info.code);
                    }
                  },
                ),
            ],
          ),
          if (snap?.fetchedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Kurs per ${TimeUtils.formatDate(TimeUtils.wib(snap!.fetchedAt!))} WIB'
              '${snap.fromCache ? ' (tersimpan)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (summary.fallbackCount > 0)
            Text(
              '${summary.fallbackCount} pengeluaran memakai kurs saat dicatat',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.tertiary,
                  ),
            ),
          if (summary.skippedCount > 0)
            Text(
              '${summary.skippedCount} pengeluaran tidak bisa dikonversi, kurs belum tersedia',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
            ),
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
                  ? 'Melebihi anggaran ${_rp(totalIdr - budget)}'
                  : 'Sisa anggaran ${_rp(budget - totalIdr)}',
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
    );
  }
}

class _WorldClock extends ConsumerWidget {
  const _WorldClock({required this.clock});

  final AsyncValue<Map<String, DateTime>> clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedZone = ref.watch(awayDayClockZoneProvider);
    final selectedIndoCity = ref.watch(awayDayClockIndoCityProvider);

    return AppCard(
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
            loading: () =>
                const SizedBox(height: 40, child: LinearProgressIndicator()),
            error: (e, _) => Text('Gagal: $e'),
            data: (times) {
              final favorite = ref.watch(favoriteClubProvider);
              final indonesiaTime = times[selectedZone] ?? times['WIB']!;
              final londonTime = times['London']!;
              final indoCity = indonesianCities.firstWhere(
                (c) => c.name == selectedIndoCity,
                orElse: () => indonesianCities.first,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('clock-zone-$selectedZone'),
                    initialValue: selectedZone,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Zona waktu Indonesia',
                      prefixIcon: Icon(Icons.schedule),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'WIB', child: Text('WIB')),
                      DropdownMenuItem(value: 'WITA', child: Text('WITA')),
                      DropdownMenuItem(value: 'WIT', child: Text('WIT')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(awayDayClockZoneProvider.notifier).state =
                            value;
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey('clock-indo-$selectedIndoCity'),
                    initialValue:
                        selectedIndoCity ?? indonesianCities.first.name,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Kota di Indonesia',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    items: [
                      for (final c in indonesianCities)
                        DropdownMenuItem(value: c.name, child: Text(c.name)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final picked =
                          indonesianCities.firstWhere((c) => c.name == value);
                      ref.read(awayDayClockIndoCityProvider.notifier).state =
                          value;
                      ref.read(awayDayClockZoneProvider.notifier).state =
                          picked.zone;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ClockReadout(
                          key: const ValueKey('clock-readout-zone'),
                          label: selectedZone,
                          time: indonesiaTime,
                          detail: 'Waktu sipil Indonesia',
                          showSeconds: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ClockReadout(
                          key: const ValueKey('clock-readout-london'),
                          label: favorite?.city ?? 'London',
                          time: londonTime,
                          detail: favorite == null
                              ? 'Pilih klub favorit untuk memakai nama kotanya'
                              : 'Jam resmi Inggris (London)',
                          showSeconds: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ClockReadout(
                    key: const ValueKey('clock-readout-indo-city'),
                    label: indoCity.name,
                    time: times[indoCity.zone] ?? times['WIB']!,
                    detail: indoCity.zone,
                    showSeconds: true,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ClockReadout extends StatelessWidget {
  const _ClockReadout({
    super.key,
    required this.label,
    required this.time,
    required this.detail,
    this.showSeconds = false,
  });

  final String label;
  final DateTime time;
  final String detail;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              showSeconds ? TimeUtils.format(time) : TimeUtils.formatHm(time),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(TimeUtils.formatDate(time), style: theme.textTheme.bodySmall),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
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
                onSelected: (_) => ref
                    .read(awayDayCategoryFilterProvider.notifier)
                    .state = null,
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
    final club = ref
        .watch(clubsProvider)
        .valueOrNull
        ?.where((c) => c.key == expense.clubKey)
        .firstOrNull;
    final crests = ref.watch(clubCrestProvider);

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
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: club != null
                ? ClubCrest(
                    crestUrl: crests[club.tla.toUpperCase()],
                    tla: club.tla,
                    color: club.colorValue,
                    size: 40,
                  )
                : CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(_catIcon[expense.category], size: 20),
                  ),
            title: Text(expense.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
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
                Text(_rp(expense.amountIdr),
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                    _foreignAmount(expense.amountForeign, expense.currencyCode),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _editBudget(BuildContext context, WidgetRef ref) async {
  final current = ref.read(awayDayBudgetProvider);
  final ctl = TextEditingController(
      text: current > 0 ? current.round().toString() : '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // UI4: judulnya "harian" padahal nilainya dipakai sebagai batas total
      // seluruh pengeluaran yang tercatat.
      title: const Text('Anggaran total'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan')),
      ],
    ),
  );
  if (saved == true) {
    final synced = await ref
        .read(awayDayBudgetProvider.notifier)
        .set(double.tryParse(ctl.text) ?? 0);
    if (!synced && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anggaran disimpan di perangkat, tetapi belum tersimpan ke akun. Akan dicoba lagi saat masuk.',
          ),
        ),
      );
    }
  }
}

Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
  final snap = ref.read(ratesProvider).valueOrNull;
  final favKey = ref.read(favoriteKeyProvider);
  final clubs = ref.read(clubsProvider).valueOrNull ?? const [];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AddForm(rates: snap?.rates, favKey: favKey, clubs: clubs),
    ),
  );
}

class _AddForm extends ConsumerStatefulWidget {
  const _AddForm(
      {required this.rates, required this.favKey, required this.clubs});

  final Map<String, double>? rates;
  final String? favKey;
  final List clubs;

  @override
  ConsumerState<_AddForm> createState() => _AddFormState();
}

class _AddFormState extends ConsumerState<_AddForm> {
  final _title = TextEditingController();
  final _foreign = TextEditingController();
  final _idr = TextEditingController();
  AwayDayCategory _cat = AwayDayCategory.tiket;
  String? _clubKey;
  String _currency = 'GBP';

  @override
  void initState() {
    super.initState();
    _clubKey =
        widget.clubs.any((c) => c.key == widget.favKey) ? widget.favKey : null;
    _foreign.addListener(_syncFromForeign);
  }

  @override
  void dispose() {
    _title.dispose();
    _foreign.dispose();
    _idr.dispose();
    super.dispose();
  }

  void _syncFromForeign([Map<String, double>? rates]) {
    if (_currency == 'IDR') return;
    final amount = parseAmount(_foreign.text);
    final availableRates =
        rates ?? ref.read(ratesProvider).valueOrNull?.rates ?? widget.rates;
    if (amount == null) {
      if (availableRates?[_currency] != null) _idr.clear();
      return;
    }
    final idr = foreignToIdr(amount, _currency, availableRates);
    if (idr != null) _idr.text = idr.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final ratesState = ref.watch(ratesProvider);
    final crests = ref.watch(clubCrestProvider);
    final outCurrency = ref.watch(awayDaySummaryCurrencyProvider);
    final snap = ratesState.valueOrNull;
    final rates = snap?.rates ?? widget.rates ?? const <String, double>{};
    final perIdr = rates[_currency];
    final rateMissing = _currency != 'IDR' && perIdr == null;
    ref.listen(ratesProvider, (_, next) {
      final latestRates = next.valueOrNull?.rates;
      if (latestRates != null) _syncFromForeign(latestRates);
    });

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Catat pengeluaran',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Keterangan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mata uang',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final info in supportedCurrencies.values)
                  DropdownMenuItem(
                    value: info.code,
                    child: Text('${info.code} \u00B7 ${info.name}'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _currency = value;
                  _foreign.clear();
                  _idr.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _foreign,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _currency != 'IDR',
              ),
              decoration: InputDecoration(
                labelText: 'Jumlah ($_currency)',
                prefixText: _currencyPrefix(_currency),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_currency != 'IDR') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _idr,
                readOnly: !rateMissing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: rateMissing
                      ? 'Nilai Rupiah (wajib diisi manual)'
                      : 'Perkiraan nilai Rupiah',
                  prefixText: 'Rp ',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (rateMissing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Kurs $_currency tidak tersedia. Isi nilai Rupiah secara manual.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              else if (snap?.fromCache == true)
                Text(
                  'Kurs tersimpan \u2022 1 $_currency = ${_rp(1 / perIdr!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (perIdr != null)
                Text(
                  'Kurs: 1 $_currency = ${_rp(1 / perIdr)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _foreign,
              builder: (context, value, _) {
                final amt = parseAmount(value.text);
                if (amt == null || amt <= 0) return const SizedBox.shrink();
                final converted =
                    convertCurrency(amt, _currency, outCurrency, rates);
                if (converted == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '\u2248 ${formatMoney(converted, outCurrency)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AwayDayCategory>(
              initialValue: _cat,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in AwayDayCategory.values)
                  DropdownMenuItem(value: c, child: Text(_catLabel[c]!)),
              ],
              onChanged: (value) =>
                  setState(() => _cat = value ?? AwayDayCategory.lainnya),
            ),
            const SizedBox(height: 12),
            if (widget.clubs.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _clubKey,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Klub', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('Umum')),
                  for (final c in widget.clubs)
                    DropdownMenuItem<String>(
                      value: c.key,
                      child: Row(children: [
                        ClubCrest(
                          crestUrl: crests[c.tla.toUpperCase()],
                          tla: c.tla,
                          color: c.colorValue,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(c.name)),
                      ]),
                    ),
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
      ),
    );
  }

  /// Kembalikan pesan galat, atau null kalau input siap disimpan.
  ///
  /// UI4: sebelumnya `_submit` langsung `return` diam-diam, jadi user menekan
  /// Simpan lalu tidak terjadi apa-apa tanpa penjelasan.
  String? validate({required bool rateMissing}) {
    if (_title.text.trim().isEmpty) return 'Keterangan belum diisi.';
    final foreign = parseAmount(_foreign.text) ?? 0;
    final idr = _currency == 'IDR' ? foreign : parseAmount(_idr.text) ?? 0;
    if (foreign <= 0) return 'Jumlah harus lebih besar dari nol.';
    if (rateMissing && idr <= 0) {
      return 'Kurs tidak tersedia. Isi nilai Rupiah secara manual.';
    }
    return null;
  }

  void _submit() {
    final rates = ref.read(ratesProvider).valueOrNull?.rates ?? widget.rates;
    final rateMissing = _currency != 'IDR' && rates?[_currency] == null;
    final problem = validate(rateMissing: rateMissing);
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final amountForeign = parseAmount(_foreign.text) ?? 0;
    final amountIdr =
        _currency == 'IDR' ? amountForeign : parseAmount(_idr.text) ?? 0;
    ref.read(awayDayProvider.notifier).add(
          title: _title.text.trim(),
          amountGbp: idrToForeign(amountIdr, 'GBP', rates) ?? 0,
          amountIdr: amountIdr,
          category: _cat,
          currencyCode: _currency,
          amountForeign: amountForeign,
          clubKey: _clubKey,
        );
    Navigator.of(context).pop();
  }
}
