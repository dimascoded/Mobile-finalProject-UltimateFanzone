import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/time_utils.dart';
import '../../trip/providers/trip_providers.dart';
import '../data/expense_repository.dart';

final ratesProvider = FutureProvider<Map<String, double>>(
    (ref) => ref.watch(expenseRepositoryProvider).fetchRates());

class ExpenseNotifier extends StateNotifier<List<Expense>> {
  ExpenseNotifier(this._repo) : super(_repo.load());
  final ExpenseRepository _repo;

  Future<void> add(String title, double amountIdr, String? countryId) async {
    state = [
      Expense(title: title, amountIdr: amountIdr, date: DateTime.now(), countryId: countryId),
      ...state,
    ];
    await _repo.save(state);
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _repo.save(state);
  }
}

final expensesProvider = StateNotifierProvider<ExpenseNotifier, List<Expense>>(
    (ref) => ExpenseNotifier(ref.watch(expenseRepositoryProvider)));

final expenseQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Pengeluaran milik Trip aktif (atau tanpa trip), terfilter kata kunci pencarian.
final tripExpensesProvider = Provider.autoDispose<List<Expense>>((ref) {
  final trip = ref.watch(tripProvider);
  final q = ref.watch(expenseQueryProvider).toLowerCase().trim();
  return ref
      .watch(expensesProvider)
      .where((e) => e.countryId == trip?.countryId)
      .where((e) => q.isEmpty || e.title.toLowerCase().contains(q))
      .toList();
});

final totalExpenseProvider = Provider.autoDispose<double>(
    (ref) => ref.watch(tripExpensesProvider).fold(0.0, (s, e) => s + e.amountIdr));

/// Jam dunia: 4 zona wajib + zona negara tujuan. Update tiap detik.
final worldClockProvider = StreamProvider.autoDispose<Map<String, DateTime>>((ref) async* {
  final c = ref.watch(activeCountryProvider);
  while (true) {
    final utc = TimeUtils.nowUtc();
    yield {
      'WIB': TimeUtils.wib(utc),
      'WITA': TimeUtils.wita(utc),
      'WIT': TimeUtils.wit(utc),
      'London': TimeUtils.london(utc),
      if (c != null) '${c.flag} ${c.tzLabel}': TimeUtils.zoneTime(utc, c.utcOffset, c.tzRule),
    };
    await Future.delayed(const Duration(seconds: 1));
  }
});
