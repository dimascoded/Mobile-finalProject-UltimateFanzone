import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/rates_provider.dart';
import '../../../core/utils/time_utils.dart';
import '../../football/providers/football_providers.dart';
import '../data/away_day_repository.dart';

/// Mata uang utama Away Day: poundsterling (tiket & menginap di Inggris).
const awayDayCurrency = 'GBP';

/// exchangerate-api.com v4 dipanggil dengan `latest/IDR`, jadi `rates['GBP']`
/// berarti "GBP per 1 Rupiah". Maka GBP -> IDR itu MEMBAGI, bukan mengali.
/// Fungsi murni agar mudah diuji (test/away_day_money_test.dart).
double? gbpToIdr(double gbp, Map<String, double>? rates) {
  final perIdr = rates?[awayDayCurrency];
  if (perIdr == null || perIdr == 0) return null;
  return gbp / perIdr;
}

/// Kebalikan dari [gbpToIdr]: Rupiah -> pound, untuk input convert.
double? idrToGbp(double idr, Map<String, double>? rates) {
  final perIdr = rates?[awayDayCurrency];
  if (perIdr == null || perIdr == 0) return null;
  return idr * perIdr;
}

// ---------- Pengeluaran ----------

class AwayDayNotifier extends StateNotifier<List<AwayDayExpense>> {
  AwayDayNotifier(this._repo) : super(_repo.load());

  final AwayDayRepository _repo;

  Future<void> add({
    required String title,
    required double amountGbp,
    required double amountIdr,
    required AwayDayCategory category,
    String? clubKey,
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

  Future<void> clearAll() async {
    state = const [];
    await _repo.save(state);
  }

  /// Terapkan hasil merge sinkronisasi (S1): daftar gabungan dari server dan
  /// perangkat ini langsung disimpan ke Hive, bukan hanya dihitung.
  Future<void> replaceAll(List<AwayDayExpense> list) async {
    state = list;
    await _repo.save(state);
  }
}

final awayDayProvider =
    StateNotifierProvider<AwayDayNotifier, List<AwayDayExpense>>(
  (ref) => AwayDayNotifier(ref.watch(awayDayRepositoryProvider)),
);

/// Teks pencarian pada daftar pengeluaran.
final awayDayQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Filter kategori; null = semua kategori.
final awayDayCategoryFilterProvider =
    StateProvider.autoDispose<AwayDayCategory?>((ref) => null);

/// Tampilkan hanya pengeluaran milik tim favorit.
final awayDayFavOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

final awayDayFilteredProvider =
    Provider.autoDispose<List<AwayDayExpense>>((ref) {
  final q = ref.watch(awayDayQueryProvider).toLowerCase().trim();
  final cat = ref.watch(awayDayCategoryFilterProvider);
  final favOnly = ref.watch(awayDayFavOnlyProvider);
  final favKey = ref.watch(favoriteKeyProvider);

  return ref.watch(awayDayProvider).where((e) {
    if (cat != null && e.category != cat) return false;
    if (favOnly && favKey != null && e.clubKey != favKey) return false;
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.category.name.toLowerCase().contains(q);
  }).toList();
});

/// Total pengeluaran dalam Rupiah dan poundsterling.
final awayDayTotalsProvider = Provider<({double idr, double gbp})>((ref) {
  var idr = 0.0;
  var gbp = 0.0;
  for (final e in ref.watch(awayDayProvider)) {
    idr += e.amountIdr;
    gbp += e.amountGbp;
  }
  return (idr: idr, gbp: gbp);
});

/// Pengeluaran per kategori untuk bar ringkas.
final awayDayByCategoryProvider = Provider<Map<AwayDayCategory, double>>((ref) {
  final out = <AwayDayCategory, double>{};
  for (final e in ref.watch(awayDayProvider)) {
    out[e.category] = (out[e.category] ?? 0) + e.amountIdr;
  }
  return out;
});

// ---------- Anggaran (disimpan di Hive, bukan StateProvider) ----------

class BudgetNotifier extends StateNotifier<double> {
  BudgetNotifier(this._repo) : super(_repo.loadBudget());

  final AwayDayRepository _repo;

  Future<void> set(double idr) async {
    state = idr < 0 ? 0 : idr;
    await _repo.saveBudget(state);
  }
}

final awayDayBudgetProvider = StateNotifierProvider<BudgetNotifier, double>(
    (ref) => BudgetNotifier(ref.watch(awayDayRepositoryProvider)));

// ---------- Jam dunia (rubrik: WIB / WITA / WIT / London) ----------

/// Semua klub Premier League basing di Inggris, jadi zona yang relevan adalah
/// WIB, WITA, WIT, dan London (Europe/London, DST ikut dihitung oleh TimeUtils).
final worldClockProvider =
    StreamProvider.autoDispose<Map<String, DateTime>>((ref) async* {
  while (true) {
    final utc = TimeUtils.nowUtc();
    yield {
      'WIB': TimeUtils.wib(utc),
      'WITA': TimeUtils.wita(utc),
      'WIT': TimeUtils.wit(utc),
      'London': TimeUtils.london(utc),
    };
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Kurs GBP per 1 Rupiah (null saat offline / gagal fetch).
final gbpRateProvider = Provider<double?>((ref) {
  final rates = ref.watch(ratesProvider).valueOrNull;
  return rates?[awayDayCurrency];
});
