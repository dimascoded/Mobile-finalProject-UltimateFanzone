import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../football/data/models.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/providers/football_providers.dart';
import '../../domain/club_card.dart';
import '../../providers/gamification_providers.dart';
import '../card_collection_screen.dart';

/// Menampilkan overlay reveal untuk [card] sekali.
Future<void> showCardRevealOverlay(BuildContext context, ClubCard card) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Kartu baru terbuka',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => CardRevealOverlay(card: card),
    transitionBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Pendengar global: begitu ada kartu baru dicetak, tampilkan reveal lalu reset
/// provider agar tidak tampil dua kali.
class CardRevealListener extends ConsumerWidget {
  const CardRevealListener({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ClubCard?>(lastEarnedCardProvider, (previous, next) {
      if (next == null) return;
      ref.read(lastEarnedCardProvider.notifier).state = null;
      showCardRevealOverlay(context, next);
    });
    return child;
  }
}

/// Kekuatan glow/scale mengikuti kelangkaan; epik & legendaris lebih kuat.
double _rarityStrength(CardRarity rarity) => switch (rarity) {
      CardRarity.common => 0.4,
      CardRarity.rare => 0.7,
      CardRarity.epic => 1.0,
      CardRarity.legendary => 1.4,
    };

/// Overlay kartu: punggung kartu berputar (rotateY) lalu membuka wajah klub,
/// disusul denyut glow/scale sesuai kelangkaan. Flip dilewati bila pengguna
/// menonaktifkan animasi.
class CardRevealOverlay extends ConsumerStatefulWidget {
  const CardRevealOverlay({super.key, required this.card});

  final ClubCard card;

  @override
  ConsumerState<CardRevealOverlay> createState() => _CardRevealOverlayState();
}

class _CardRevealOverlayState extends ConsumerState<CardRevealOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _flip;
  late final AnimationController _pulse;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _flip.value = 1;
    } else {
      _flip.forward().whenComplete(() {
        if (!mounted) return;
        _pulse.forward().then((_) {
          if (mounted) _pulse.reverse();
        });
      });
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _openCollection() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute<void>(builder: (_) => const CardCollectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final clubs = ref.watch(clubsProvider).valueOrNull ?? const <PlClub>[];
    PlClub? club;
    for (final c in clubs) {
      if (c.key == card.clubKey) {
        club = c;
        break;
      }
    }
    final crestUrl = club == null
        ? null
        : ref.watch(clubCrestProvider)[club.tla.toUpperCase()];
    final clubName = club?.name ?? card.clubKey;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Kartu baru!',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: Listenable.merge([_flip, _pulse]),
                  builder: (context, _) => _buildCard(
                    clubName: clubName,
                    crestUrl: crestUrl,
                    club: club,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Tutup'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _openCollection,
                      icon: const Icon(Icons.style_outlined),
                      label: const Text('Lihat Koleksi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String clubName,
    required String? crestUrl,
    required PlClub? club,
  }) {
    final angle = _flip.value * math.pi;
    final showFront = angle > math.pi / 2;

    final Widget face = showFront
        ? _FrontFace(
            clubName: clubName,
            crestUrl: crestUrl,
            club: club,
            rarity: widget.card.rarity,
          )
        : const _BackFace();

    final strength = _rarityStrength(widget.card.rarity);
    final scale = showFront ? 1 + 0.06 * _pulse.value * strength : 1.0;

    return Transform.scale(
      scale: scale,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle),
        child: showFront
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(math.pi),
                child: face,
              )
            : face,
      ),
    );
  }
}

class _BackFace extends StatelessWidget {
  const _BackFace();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primaryContainer],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_soccer, size: 72, color: scheme.onPrimary),
          const SizedBox(height: 12),
          Text(
            'Membuka kartu...',
            style:
                TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FrontFace extends StatelessWidget {
  const _FrontFace({
    required this.clubName,
    required this.crestUrl,
    required this.club,
    required this.rarity,
  });

  final String clubName;
  final String? crestUrl;
  final PlClub? club;
  final CardRarity rarity;

  @override
  Widget build(BuildContext context) {
    final color = rarityColor(rarity);
    final strength = _rarityStrength(rarity);
    return Container(
      width: 220,
      height: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25 * strength),
            blurRadius: 24 * strength,
            spreadRadius: 2 * strength,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClubCrest(
            crestUrl: crestUrl,
            tla: club?.tla ?? '?',
            color: club?.colorValue,
            size: 96,
          ),
          const SizedBox(height: 16),
          Text(
            clubName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              rarityLabel(rarity),
              style: TextStyle(
                color: rarity == CardRarity.legendary
                    ? Colors.black
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
