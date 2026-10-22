import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_card.dart';
import '../../../../core/ui/pill_badge.dart';
import '../../../../core/ui/section_header.dart';
import '../../../football/data/models.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/providers/football_providers.dart';
import '../../../gamification/domain/club_card.dart';
import '../../../gamification/presentation/card_collection_screen.dart';
import '../../../gamification/providers/card_collection_provider.dart';
import '../../../penalty_shootout/presentation/penalty_screen.dart';

// STRUKTUR UI — CardsTeaser
// Ukuran: Column tanpa Scaffold: SectionHeader + isi, jarak AppSpacing.md.
// [1] Kartu kosong    — AppCard ajakan bermain Adu Penalti bila koleksi
//                        klub masih kosong
// [2] Baris kartu     — Row berisi maksimal tiga _CardTile (Expanded)
// [3] _CardTile       — kartu klub: crest, nama pendek, dan PillBadge
//                        kelangkaan kartu
// [4] _TextBadge      — badge lingkaran 36px berisi tiga huruf kode klub
// Tabel/kolom: tanpa tabel; baris kartu tiga kolom saat koleksi terisi.
// Sumber data: cardCollectionProvider, clubsProvider, clubCrestProvider.
/// Tiga kartu klub terbaru, atau ajakan bermain bila koleksi masih kosong.
class CardsTeaser extends ConsumerWidget {
  const CardsTeaser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = [...ref.watch(cardCollectionProvider)]
      ..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
    final clubs = ref.watch(clubsProvider).valueOrNull ?? const <PlClub>[];
    final crests = ref.watch(clubCrestProvider);

    void openCollection() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CardCollectionScreen()),
        );

    final header = SectionHeader(
      title: 'Kartu Klub terbaru',
      actionLabel: 'Koleksi',
      onAction: openCollection,
    );

    if (cards.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          AppCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PenaltyScreen()),
            ),
            child: Text(
              'Belum ada kartu. Main Adu Penalti atau tebak skor untuk '
              'mendapat kartu pertamamu.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    final top = cards.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _CardTile(
                  card: top[i],
                  club: _clubByKey(clubs, top[i].clubKey),
                  crests: crests,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static PlClub? _clubByKey(List<PlClub> clubs, String key) {
    for (final c in clubs) {
      if (c.key == key) return c;
    }
    return null;
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile(
      {required this.card, required this.club, required this.crests});

  final ClubCard card;
  final PlClub? club;
  final Map<String, String> crests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final club = this.club;
    final isRare =
        card.rarity == CardRarity.epic || card.rarity == CardRarity.legendary;

    final Widget crest = club == null
        ? _TextBadge(text: card.clubKey)
        : ClubCrest(
            crestUrl: crests[club.tla.toUpperCase()],
            tla: club.tla,
            color: club.colorValue,
            size: 36,
          );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          crest,
          const SizedBox(height: AppSpacing.sm),
          Text(
            club?.shortName ?? card.clubKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          PillBadge(
            label: rarityLabel(card.rarity),
            tone: isRare ? PillTone.accent : PillTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _TextBadge extends StatelessWidget {
  const _TextBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = text.isEmpty
        ? '?'
        : text.substring(0, text.length < 3 ? text.length : 3).toUpperCase();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
