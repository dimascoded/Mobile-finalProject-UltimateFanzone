import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../away_day/providers/away_day_providers.dart';
import '../../football/providers/football_providers.dart';
import '../../gamification/providers/gamification_providers.dart';

/// Ringkasan angka privat pengguna: pengeluaran, stamp, dan tebakan.
///
/// Tim favorit dan laga berikutnya TIDAK diulang di sini karena keduanya sudah
/// tampil di `FavoriteTeamCard` (UI1: sebelumnya dua kartu menampilkan data
/// yang sama).
class FanSummary extends ConsumerWidget {
  const FanSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final club = ref.watch(favoriteClubProvider);
    if (club == null) return const SizedBox.shrink();

    final totals = ref.watch(awayDayTotalsProvider);
    final budget = ref.watch(awayDayBudgetProvider);
    final chain = ref.watch(stampsProvider);
    final stamps = chain.where((b) => b.data['club'] == club.key).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: _Stat(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Away Day',
              value: 'Rp ${totals.idr.round()}',
              detail: budget > 0
                  ? 'dari Rp ${budget.round()}'
                  : 'belum ada anggaran',
            ),
          ),
          Expanded(
            child: _Stat(
              icon: Icons.approval,
              label: 'Stamp',
              value: '$stamps',
              detail: 'di ${club.name}',
            ),
          ),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value, $detail',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: theme.textTheme.bodySmall),
          Text(detail,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
