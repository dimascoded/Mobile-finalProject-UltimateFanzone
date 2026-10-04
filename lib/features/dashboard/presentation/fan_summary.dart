import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../football/providers/football_providers.dart';

class FanSummary extends ConsumerWidget {
  const FanSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    if (club == null) return const SizedBox.shrink();
    final total = ref.watch(awayDayTotalProvider);
    final budget = ref.watch(awayDayBudgetProvider);
    final stamps = ref.watch(stampsProvider).where((b) => b.data['club'] == club.key).length;
    final next = ref.watch(nextMatchProvider).valueOrNull;
    return Card(
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.sports_soccer),
          title: const Text('Tim Favorit'),
          subtitle: Text('${club.name} • ${club.stadium}'),
        ),
        if (next != null)
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Laga berikutnya'),
            subtitle: Text('${next.homeShort} vs ${next.awayShort}'),
          ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Away Day'),
          subtitle: Text('Rp ${total.toStringAsFixed(0)} ${budget > 0 ? 'dari Rp ${budget.toStringAsFixed(0)}' : ''}'),
        ),
        ListTile(
          leading: const Icon(Icons.approval),
          title: const Text('Stamp stadion'),
          subtitle: Text('$stamps stamp'),
        ),
      ]),
    );
  }
}