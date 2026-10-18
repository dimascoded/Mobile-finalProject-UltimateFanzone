import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../football/data/models.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../domain/club_card.dart';
import '../providers/card_collection_provider.dart';
import '../providers/gamification_providers.dart';

/// Warna label per tingkat kelangkaan.
Color rarityColor(CardRarity rarity) => switch (rarity) {
      CardRarity.common => const Color(0xFF6B7280),
      CardRarity.rare => const Color(0xFF2563EB),
      CardRarity.epic => const Color(0xFF7C3AED),
      CardRarity.legendary => const Color(0xFFD4AF37),
    };

/// Label teks per tingkat kelangkaan. Warna tidak pernah berdiri sendiri.
String rarityLabel(CardRarity rarity) => switch (rarity) {
      CardRarity.common => 'Biasa',
      CardRarity.rare => 'Langka',
      CardRarity.epic => 'Epik',
      CardRarity.legendary => 'Legendaris',
    };

/// Sumber kartu dalam bahasa sehari-hari.
String cardSourceLabel(String source) => switch (source) {
      'penalty' => 'Dari Adu Penalti',
      'reflex' => 'Dari Refleks Kiper',
      'prediction' => 'Dari prediksi yang tepat',
      'rank' => 'Dari peringkat prediksi',
      'stamp' => 'Dari kunjungan stadion',
      _ => source.isEmpty ? 'Sumber tidak diketahui' : 'Dari $source',
    };

/// Tanggal tanpa paket tambahan, bulan dalam bahasa Indonesia.
String formatEarnedDate(DateTime date) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

/// Hash dipersingkat: 10 karakter awal + 6 karakter akhir.
String shortHash(String hash) => hash.length <= 16
    ? hash
    : '${hash.substring(0, 10)}…${hash.substring(hash.length - 6)}';

/// Alamat pemilik dipersingkat: 6 karakter awal + 4 karakter akhir.
String shortOwner(String owner) => owner.length <= 10
    ? owner
    : '${owner.substring(0, 6)}…${owner.substring(owner.length - 4)}';

class CardCollectionScreen extends ConsumerStatefulWidget {
  const CardCollectionScreen({super.key});

  @override
  ConsumerState<CardCollectionScreen> createState() =>
      _CardCollectionScreenState();
}

class _CardCollectionScreenState extends ConsumerState<CardCollectionScreen> {
  CardRarity? _selectedRarity;

  @override
  Widget build(BuildContext context) {
    final clubsAsync = ref.watch(clubsProvider);
    final cards = ref.watch(cardCollectionProvider);
    final rarityCounts = ref.watch(cardRarityCountsProvider);
    final valid = ref.watch(chainValidProvider);
    final crests = ref.watch(clubCrestProvider);
    final entries = ref.watch(collectionEntriesProvider);

    final clubs = clubsAsync.valueOrNull ?? const <PlClub>[];
    final clubByKey = {for (final c in clubs) c.key: c};
    final ownedClubsSet = {for (final c in cards) c.clubKey};

    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);

    if (clubsAsync.isLoading && clubs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Koleksi Kartu')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalCards = cards.length;
    final collectedClubs = ownedClubsSet.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Koleksi Kartu')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Header(
            collected: collectedClubs,
            total: clubs.length,
            counts: rarityCounts,
            totalCards: totalCards,
          ),
          const SizedBox(height: AppSpacing.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Semua',
                  selected: _selectedRarity == null,
                  onSelected: () => setState(() => _selectedRarity = null),
                  count: entries.length,
                ),
                const SizedBox(width: AppSpacing.sm),
                for (final rarity in CardRarity.values) ...[
                  _FilterChip(
                    label: rarityLabel(rarity),
                    selected: _selectedRarity == rarity,
                    onSelected: () => setState(() => _selectedRarity = rarity),
                    count: rarityCounts[rarity] ?? 0,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (cards.isEmpty)
            const _EmptyState()
          else
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 600 ? 3 : 2;
              final filteredEntries = _selectedRarity == null
                  ? entries
                  : entries.where((e) => e.rarity == _selectedRarity).toList();
              return _selectedRarity == null
                  ? GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredEntries.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent: 196 * textScale,
                      ),
                      itemBuilder: (context, i) {
                        final entry = filteredEntries[i];
                        final club = clubByKey[entry.clubKey];
                        if (club == null) return const SizedBox.shrink();
                        return _CollectionEntryTile(
                          club: club,
                          entry: entry,
                          crestUrl: crests[club.tla.toUpperCase()],
                          owned: true,
                        );
                      },
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: clubs.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppSpacing.md,
                        mainAxisSpacing: AppSpacing.md,
                        mainAxisExtent: 196 * textScale,
                      ),
                      itemBuilder: (context, i) {
                        final club = clubs[i];
                        final entry = entries.firstWhere(
                          (e) =>
                              e.clubKey == club.key &&
                              e.rarity == _selectedRarity,
                          orElse: () => CollectionEntry(
                            clubKey: club.key,
                            rarity: _selectedRarity!,
                            cards: const <ClubCard>[],
                          ),
                        );
                        final owned = entry.cards.isNotEmpty;
                        return _CollectionEntryTile(
                          club: club,
                          entry: entry,
                          crestUrl: crests[club.tla.toUpperCase()],
                          owned: owned,
                        );
                      },
                    );
            }),
          const SizedBox(height: AppSpacing.lg),
          _ChainFooter(valid: valid),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.collected,
    required this.total,
    required this.counts,
    required this.totalCards,
  });

  final int collected;
  final int total;
  final Map<CardRarity, int> counts;
  final int totalCards;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : collected / total;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$collected dari $total klub terkumpul',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$totalCards kartu',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final rarity in CardRarity.values)
                _RarityChip(
                  rarity: rarity,
                  count: counts[rarity] ?? 0,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RarityChip extends StatelessWidget {
  const _RarityChip({required this.rarity, required this.count});

  final CardRarity rarity;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              '${rarityLabel(rarity)} $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}

class _CollectionEntryTile extends StatelessWidget {
  const _CollectionEntryTile({
    required this.club,
    required this.entry,
    required this.crestUrl,
    required this.owned,
  });

  final PlClub club;
  final CollectionEntry entry;
  final String? crestUrl;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rarity = entry.rarity;
    final color = rarityColor(rarity);
    final count = entry.count;
    return Opacity(
      opacity: owned ? 1.0 : 0.5,
      child: AppCard(
        onTap: owned
            ? () => _showEntryDetails(context, club, entry, crestUrl)
            : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: owned ? color : scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      ClubCrest(
                        crestUrl: crestUrl,
                        tla: club.tla,
                        color: club.colorValue,
                        size: 64,
                      ),
                      if (!owned)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Icon(
                            Icons.lock_outline,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    club.shortName.isNotEmpty ? club.shortName : club.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      count > 1
                          ? '${rarityLabel(rarity)} x$count'
                          : rarityLabel(rarity),
                      style: TextStyle(
                        color: rarity == CardRarity.legendary
                            ? Colors.black
                            : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Icon(
            Icons.style_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Main Adu Penalti, Refleks Kiper, atau tebak skor untuk '
            'mendapat kartu pertamamu.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ChainFooter extends StatelessWidget {
  const _ChainFooter({required this.valid});

  final bool valid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            valid ? Icons.check_circle : Icons.warning_amber_rounded,
            color: valid ? scheme.primary : scheme.error,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              valid ? 'Riwayat aman' : 'Riwayat tidak cocok',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void _showEntryDetails(
  BuildContext context,
  PlClub club,
  CollectionEntry entry,
  String? crestUrl,
) {
  final cards = entry.cards;
  final newest = entry.newest;
  final rarity = entry.rarity;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClubCrest(
                  crestUrl: crestUrl,
                  tla: club.tla,
                  color: club.colorValue,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    club.name,
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Kelangkaan: ${rarityLabel(rarity)}'),
            const SizedBox(height: 4),
            Text('Jumlah: ${entry.count} kartu'),
            const SizedBox(height: 4),
            Text('Sumber terbaru: ${cardSourceLabel(newest.source)}'),
            const SizedBox(height: 4),
            Text('Didapat terbaru: ${formatEarnedDate(newest.earnedAt)}'),
            const Divider(height: 32),
            Text(
              'Bukti keaslian',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'ID Pemilik: ${shortOwner(newest.owner)}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Catatan #${newest.blockIndex}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    shortHash(newest.blockHash),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: 'Salin kode unik',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: newest.blockHash));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Kode unik disalin')),
                      );
                    }
                  },
                ),
              ],
            ),
            if (cards.length > 1) ...[
              const Divider(height: 32),
              Text(
                'Sumber lainnya',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...cards.skip(1).map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${cardSourceLabel(c.source)} (${formatEarnedDate(c.earnedAt)})',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            Text(
              'Klub dan kelangkaan kartu ini ditentukan dari kode unik '
              'di atas, jadi tidak bisa diubah setelah dicetak.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
