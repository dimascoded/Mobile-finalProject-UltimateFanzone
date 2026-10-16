import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class CardCollectionScreen extends ConsumerWidget {
  const CardCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubsAsync = ref.watch(clubsProvider);
    final cards = ref.watch(cardCollectionProvider);
    final rarityCounts = ref.watch(cardRarityCountsProvider);
    final valid = ref.watch(chainValidProvider);
    final crests = ref.watch(clubCrestProvider);

    final clubs = clubsAsync.valueOrNull ?? const <PlClub>[];
    final byClub = <String, List<ClubCard>>{};
    for (final c in cards) {
      byClub.putIfAbsent(c.clubKey, () => <ClubCard>[]).add(c);
    }
    final clubKeys = {for (final c in clubs) c.key};
    final collected = byClub.keys.where(clubKeys.contains).length;

    if (clubsAsync.isLoading && clubs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Koleksi Kartu')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Koleksi Kartu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            collected: collected,
            total: clubs.length,
            counts: rarityCounts,
          ),
          const SizedBox(height: 16),
          if (cards.isEmpty)
            const _EmptyState()
          else
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 600 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: clubs.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 196,
                ),
                itemBuilder: (context, i) {
                  final club = clubs[i];
                  return _ClubTile(
                    club: club,
                    cards: byClub[club.key] ?? const <ClubCard>[],
                    crestUrl: crests[club.tla.toUpperCase()],
                  );
                },
              );
            }),
          const SizedBox(height: 16),
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
  });

  final int collected;
  final int total;
  final Map<CardRarity, int> counts;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : collected / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
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
          const SizedBox(width: 6),
          Text('${rarityLabel(rarity)} $count'),
        ],
      ),
    );
  }
}

class _ClubTile extends StatelessWidget {
  const _ClubTile({
    required this.club,
    required this.cards,
    required this.crestUrl,
  });

  final PlClub club;
  final List<ClubCard> cards;
  final String? crestUrl;

  CardRarity get _highestRarity {
    var rarity = cards.first.rarity;
    for (final c in cards) {
      if (c.rarity.index > rarity.index) rarity = c.rarity;
    }
    return rarity;
  }

  @override
  Widget build(BuildContext context) {
    final owned = cards.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            owned ? () => _showDetails(context, club, cards, crestUrl) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: owned
                ? _ownedContent(context, scheme)
                : _unownedContent(scheme),
          ),
        ),
      ),
    );
  }

  List<Widget> _ownedContent(BuildContext context, ColorScheme scheme) {
    final rarity = _highestRarity;
    final color = rarityColor(rarity);
    return [
      ClubCrest(
        crestUrl: crestUrl,
        tla: club.tla,
        color: club.colorValue,
        size: 64,
      ),
      const SizedBox(height: 8),
      Text(
        club.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          cards.length > 1
              ? '${rarityLabel(rarity)} x${cards.length}'
              : rarityLabel(rarity),
          style: TextStyle(
            color: rarity == CardRarity.legendary ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];
  }

  List<Widget> _unownedContent(ColorScheme scheme) => [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Text(
            '?',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.style_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'Main Adu Penalti, Refleks Kiper, atau tebak skor untuk '
              'mendapat kartu pertamamu.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainFooter extends StatelessWidget {
  const _ChainFooter({required this.valid});

  final bool valid;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          valid ? Icons.check_circle : Icons.warning_amber_rounded,
          color: valid ? Colors.green : Colors.orange,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(valid ? 'Riwayat aman' : 'Riwayat tidak cocok'),
      ],
    );
  }
}

void _showDetails(
    BuildContext context, PlClub club, List<ClubCard> cards, String? crestUrl) {
  final highest = cards.first;
  final rarity = cards.fold(
    highest.rarity,
    (r, c) => c.rarity.index > r.index ? c.rarity : r,
  );
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
            Text(cardSourceLabel(highest.source)),
            const SizedBox(height: 4),
            Text('Didapat ${formatEarnedDate(highest.earnedAt)}'),
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
              'ID Pemilik: ${shortOwner(highest.owner)}',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text('Catatan #${highest.blockIndex}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    shortHash(highest.blockHash),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: 'Salin kode unik',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: highest.blockHash));
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Kode unik disalin')),
                      );
                    }
                  },
                ),
              ],
            ),
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
