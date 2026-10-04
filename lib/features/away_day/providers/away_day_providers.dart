import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/rates_provider.dart';
import '../data/away_day_repository.dart';
import '../../football/providers/football_providers.dart';

class AwayDayNotifier extends StateNotifier<List<AwayDayExpense>> {
  AwayDayNotifier(this._repo) : super(_repo.load());
  final AwayDayRepository _repo;

  Future<void> add({
    required String title,
    required double amountGbp,
    required double amountIdr,
    required AwayDayCategory category,
    required String? clubKey,
  }) async {
    state = [
      AwayDayExpense(
        title: title,
        amountGbp: amountGbp,
        amountIdr: amountIdr,
        category: category,
        date: DateTime.now(),
        clubKey: clubKey,
      ),
      ...state,
    ];
    await _repo.save(state);
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _repo.save(state);
  }
}

final awayDayProvider = StateNotifierProvider<AwayDayNotifier, List<AwayDayExpense>>(
  (ref) => AwayDayNotifier(ref.watch(awayDayRepositoryProvider)),
);

final awayDayQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final awayDayFilteredProvider = Provider.autoDispose<List<AwayDayExpense>>((ref) {
  final q = ref.watch(awayDayQueryProvider).toLowerCase().trim();
  return ref.watch(awayDayProvider).where((e) {
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) || e.category.name.toLowerCase().contains(q);
  }).toList();
});

final awayDayTotalProvider = Provider<double>(
  (ref) => ref.watch(awayDayProvider).fold(0.0, (s, e) => s + e.amountIdr),
);

final awayDayGbpRateProvider = Provider<double>((ref) {
  final rates = ref.watch(ratesProvider).valueOrNull;
  if (rates == null) return 0;
  // 1 GBP -> IDR? API gives rates for base IDR? AppConfig: exchangeRateUrl uses latest/IDR
  // So rate[GBP] is how many IDR per 1 GBP? (higher number) - to convert GBP->IDR: amountIdr = amountGbp * rate
  final gbp = rates['GBP'];
  return gbp ?? rates.values.firstWhere((_) => false, orElse: () => 0);
});

final awayDayBudgetProvider = StateProvider<double>((ref) => 0);