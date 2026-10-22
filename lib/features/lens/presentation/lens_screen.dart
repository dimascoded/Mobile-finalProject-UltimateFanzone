import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/rates_provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/presentation/auto_lock_observer.dart';
import '../../away_day/data/away_day_repository.dart';
import '../../away_day/presentation/away_day_screen.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../football/data/models.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/presentation/match_center_screen.dart';
import '../../football/providers/football_providers.dart';
import '../data/expense_mapper.dart';
import '../data/receipt_parser.dart';
import '../providers/lens_provider.dart';

const _catLabel = {
  AwayDayCategory.tiket: 'Tiket',
  AwayDayCategory.hotel: 'Hotel',
  AwayDayCategory.transport: 'Transportasi',
  AwayDayCategory.merchandise: 'Merchandise',
  AwayDayCategory.makanan: 'Makanan',
  AwayDayCategory.lainnya: 'Lainnya',
};

// STRUKTUR UI — LensScreen
// Ukuran: Scaffold + AppBar, body Center + ConstrainedBox(maxWidth: 720) + Column;
// hasil scan ditampilkan di _ResultView (ListView)
// [1] Pemilih jenis dokumen — SegmentedButton Otomatis/Struk/Tiket + tips pencahayaan
// [2] Pemicu pemindaian — Row tombol Kamera dan Galeri, plus LinearProgressIndicator saat busy
// [3] _ResultView — hasil scan: _ImagePreview, kartu _ExpenseCard, ExpansionTile teks OCR
// [4] _ExpenseCard — form disunting: keterangan, jumlah, nominal alternatif, mata uang, kategori
// [5] Info tiket — klub terdeteksi, laga terkait, tombol lihat jadwal klub
// [6] Penyimpanan — ringkasan konversi Rupiah dan tombol simpan ke Away Day
// Tabel/kolom: tanpa tabel; daftar kartu satu kolom, pilihan nominal/kategori memakai Wrap Chip
// Sumber data: lensProvider, ratesProvider, matchesProvider, clubCrestProvider,
// awayDayProvider, favoriteKeyProvider, matchQueryProvider

class LensScreen extends ConsumerStatefulWidget {
  const LensScreen({super.key});

  @override
  ConsumerState<LensScreen> createState() => _LensScreenState();
}

class _LensScreenState extends ConsumerState<LensScreen> {
  /// null = Otomatis (biarkan parser menentukan jenis dokumen).
  DocKind? _forceKind;

  Future<void> _scan(ImageSource source) => withoutAutoLock(
        ref,
        () =>
            ref.read(lensProvider.notifier).scan(source, forceKind: _forceKind),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lensProvider);
    final busy = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Struk & Tiket'),
        actions: [
          if (state.hasValue && state.value != null)
            IconButton(
              tooltip: 'Hapus hasil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(lensProvider.notifier).clear(),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<DocKind?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Otomatis')),
                        ButtonSegment(
                            value: DocKind.receipt, label: Text('Struk')),
                        ButtonSegment(
                            value: DocKind.ticket, label: Text('Tiket')),
                      ],
                      selected: {_forceKind},
                      onSelectionChanged: (s) =>
                          setState(() => _forceKind = s.first),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pastikan seluruh struk terlihat, terang, dan tidak buram.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Ambil foto struk atau tiket',
                        child: FilledButton.icon(
                          onPressed:
                              busy ? null : () => _scan(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Kamera'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Pilih foto dari galeri',
                        child: OutlinedButton.icon(
                          onPressed:
                              busy ? null : () => _scan(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Galeri'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const LinearProgressIndicator(semanticsLabel: 'Memproses foto'),
              Expanded(
                child: state.when(
                  skipLoadingOnRefresh: true,
                  data: (r) => r == null
                      ? const EmptyState(
                          icon: Icons.document_scanner,
                          title: 'Belum ada hasil',
                          message:
                              'Ambil foto struk atau tiket. Teks akan dibaca otomatis '
                              'lalu diisi ke kartu pengeluaran yang bisa disunting.',
                        )
                      : _ResultView(result: r),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => EmptyState(
                    icon: Icons.error_outline,
                    title: 'Scan gagal',
                    message: e.toString().replaceFirst('Exception: ', ''),
                    action: OutlinedButton.icon(
                      onPressed: () => _scan(ImageSource.camera),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final LensResult result;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (result.imagePath.isNotEmpty) _ImagePreview(path: result.imagePath),
        const SizedBox(height: AppSpacing.md),
        _ExpenseCard(
          key: ValueKey(result.imagePath),
          result: result,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            title: const Text('Teks yang terbaca dari foto'),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: SelectableText(
                  result.text.trim().isEmpty ? '(kosong)' : result.text,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kartu pengeluaran yang bisa disunting. Keyed by imagePath (lihat
/// [_ResultView]) supaya controller di-inisialisasi ulang tiap pemindaian baru.
class _ExpenseCard extends ConsumerStatefulWidget {
  const _ExpenseCard({required this.result, super.key});

  final LensResult result;

  @override
  ConsumerState<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends ConsumerState<_ExpenseCard> {
  late final TextEditingController _title =
      TextEditingController(text: widget.result.draft.title);
  late final TextEditingController _amount =
      TextEditingController(text: _amountText(widget.result.draft.amount));
  final _manualIdr = TextEditingController();
  late String _currency = widget.result.draft.currency;
  late AwayDayCategory _category = widget.result.draft.category;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _manualIdr.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, double>? rates) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final title = _title.text.trim();
    final amountForeign = parseAmount(_amount.text);
    final manualIdr = parseAmount(_manualIdr.text);

    String? problem;
    if (title.isEmpty) {
      problem = 'Keterangan belum diisi.';
    }

    ({double amountForeign, double amountIdr, double amountGbp})? mapped;
    if (problem == null) {
      mapped = amountForeign == null
          ? null
          : toExpenseAmounts(
              amountForeign: amountForeign,
              currency: _currency,
              rates: rates,
              manualIdr: manualIdr,
            );
      if (mapped == null) {
        problem = (_currency != 'IDR' && rates?[_currency] == null)
            ? 'Kurs $_currency tidak tersedia. Isi nilai Rupiah manual.'
            : 'Jumlah harus lebih besar dari nol.';
      }
    }

    if (problem != null || mapped == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem!)));
      return;
    }

    final favKey = ref.read(favoriteKeyProvider);
    final clubKey = favKey ??
        (widget.result.draft.clubs.isNotEmpty
            ? widget.result.draft.clubs.first.key
            : null);

    setState(() => _saving = true);
    await ref.read(awayDayProvider.notifier).add(
          title: title,
          amountGbp: mapped.amountGbp,
          amountIdr: mapped.amountIdr,
          category: _category,
          currencyCode: _currency,
          amountForeign: mapped.amountForeign,
          clubKey: clubKey,
        );
    if (!mounted) return;

    ref.read(lensProvider.notifier).clear();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Tersimpan ke Away Day'),
          action: SnackBarAction(
            label: 'Buka',
            onPressed: () => navigator.push(
              MaterialPageRoute(builder: (_) => const AwayDayScreen()),
            ),
          ),
        ),
      );
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.result.draft;

    final rates = ref.watch(ratesProvider).valueOrNull?.rates;
    final amountForeign = parseAmount(_amount.text);
    final manualIdr = parseAmount(_manualIdr.text);
    final mapped = amountForeign == null
        ? null
        : toExpenseAmounts(
            amountForeign: amountForeign,
            currency: _currency,
            rates: rates,
            manualIdr: manualIdr,
          );
    final rateMissing = _currency != 'IDR' && rates?[_currency] == null;

    final matches = ref.watch(matchesProvider).valueOrNull?.data ?? const [];
    final crests = ref.watch(clubCrestProvider);
    FootballMatch? linked;
    if (draft.matchId != null) {
      for (final m in matches) {
        if (m.id == draft.matchId) {
          linked = m;
          break;
        }
      }
    }

    final otherCandidates = draft.candidates
        .where((c) => (c.amount - (draft.amount ?? -1)).abs() > 0.0001)
        .toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                draft.kind == DocKind.ticket
                    ? Icons.confirmation_number_outlined
                    : Icons.receipt_long_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                draft.kind == DocKind.ticket ? 'Tiket' : 'Struk',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Keterangan',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.numberWithOptions(
              decimal: _currency != 'IDR',
            ),
            decoration: InputDecoration(
              labelText: 'Jumlah ($_currency)',
              prefixText: _currencyPrefix(_currency),
              border: const OutlineInputBorder(),
            ),
          ),
          if (otherCandidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Nominal lain yang terbaca',
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in otherCandidates)
                  ChoiceChip(
                    label: Text(_amountText(c.amount)),
                    selected: false,
                    onSelected: (_) =>
                        setState(() => _amount.text = _amountText(c.amount)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mata uang',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final currency in awayDayCurrencies)
                DropdownMenuItem(value: currency, child: Text(currency)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _currency = value;
                _manualIdr.clear();
              });
            },
          ),
          if (draft.currencyGuessed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Mata uang ditebak, periksa dulu',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Kategori', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in AwayDayCategory.values)
                ChoiceChip(
                  label: Text(_catLabel[c]!),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (mapped != null)
            Text('Setara ${_rp(mapped.amountIdr)}',
                style: theme.textTheme.titleMedium)
          else if (rateMissing)
            Text('Kurs $_currency tidak tersedia.',
                style: theme.textTheme.bodyMedium),
          if (rateMissing) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _manualIdr,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Nilai Rupiah (wajib diisi manual)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (draft.kind == DocKind.ticket) ...[
            const SizedBox(height: 12),
            if (draft.clubs.isNotEmpty) ...[
              Text('Klub terdeteksi', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in draft.clubs)
                    Chip(
                      avatar: ClubCrest(
                        crestUrl: crests[c.tla.toUpperCase()],
                        tla: c.tla,
                        color: c.colorValue,
                        size: 24,
                      ),
                      label: Text(c.name),
                    ),
                ],
              ),
            ],
            if (linked != null) ...[
              const SizedBox(height: 8),
              Text(
                'Laga: ${linked.homeShort} vs ${linked.awayShort}, '
                '${TimeUtils.formatDate(TimeUtils.wib(linked.kickoffUtc))} '
                '${TimeUtils.formatHm(TimeUtils.wib(linked.kickoffUtc))} WIB',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (draft.clubs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openFixtures(context, ref, draft.clubs.first),
                  icon: const Icon(Icons.event_note, size: 18),
                  label: Text('Lihat jadwal ${draft.clubs.first.shortName}'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(rates),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan ke Away Day'),
          ),
        ],
      ),
    );
  }
}

/// Buka Match Center dengan pencarian sudah terisi nama klub, jadi pengguna
/// langsung melihat jadwal klub yang terbaca di struk/karcis.
///
/// `matchQueryProvider` adalah `autoDispose`: nilainya dibuang begitu tidak ada
/// pendengar. Jadi penulisan dilakukan setelah halaman baru selesai dibangun,
/// lewat `addPostFrameCallback` di dalam `builder`.
void _openFixtures(BuildContext context, WidgetRef ref, PlClub club) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (routeContext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!routeContext.mounted) return;
        ProviderScope.containerOf(routeContext)
            .read(matchQueryProvider.notifier)
            .state = club.name;
      });
      return const MatchCenterScreen();
    },
  ));
}

/// Angka tanpa desimal bila bulat: 14.5 -> "14.5", 66000 -> "66000".
String _amountText(double? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toString();
}

String _currencyPrefix(String currency) => switch (currency) {
      'GBP' => '\u00A3 ',
      'USD' => '\$ ',
      'EUR' => '\u20AC ',
      _ => 'Rp ',
    };

/// Ribuan tanpa paket intl (tidak ada di pubspec): 1234567.89 -> "Rp1.234.568".
String _rp(double v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-Rp' : 'Rp');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// UI8: `File(...).existsSync()` di dalam build() memblokir UI thread setiap
/// frame. Dipindah ke FutureBuilder supaya sekali saja saat widget dibangun.
class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  late final Future<bool> _exists = File(widget.path).exists();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _exists,
      builder: (context, snap) {
        final ok = snap.data ?? false;
        if (!ok) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text('Foto tidak lagi tersedia di perangkat.',
                style: Theme.of(context).textTheme.bodySmall),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(
            File(widget.path),
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: 'Foto hasil pindai',
          ),
        );
      },
    );
  }
}
