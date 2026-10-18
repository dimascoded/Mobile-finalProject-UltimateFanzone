import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/rates_provider.dart';
import '../../../core/utils/time_utils.dart';
import '../../football/providers/football_providers.dart';
import '../data/away_day_repository.dart';
import '../data/currency_convert.dart';

final awayDayCurrencies = supportedCurrencies.keys.toList();

/// Rates API memakai IDR sebagai basis: `rates[code]` adalah unit asing per IDR.
double? foreignToIdr(
  double amount,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return amount;
  final rate = rates?[currency];
  if (rate == null || rate == 0) return null;
  return amount / rate;
}

double? idrToForeign(
  double idr,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return idr;
  final rate = rates?[currency];
  if (rate == null) return null;
  return idr * rate;
}

double? gbpToIdr(double gbp, Map<String, double>? rates) =>
    foreignToIdr(gbp, 'GBP', rates);

double? idrToGbp(double idr, Map<String, double>? rates) =>
    idrToForeign(idr, 'GBP', rates);

// ---------- Pengeluaran ----------

class AwayDayNotifier extends StateNotifier<List<AwayDayExpense>> {
  AwayDayNotifier(this._repo) : super(_repo.load());

  final AwayDayRepository _repo;

  Future<void> add({
    required String title,
    required double amountGbp,
    required double amountIdr,
    required AwayDayCategory category,
    String currencyCode = 'GBP',
    double? amountForeign,
    String? clubKey,
  }) async {
    state = [
      AwayDayExpense(
        title: title,
        amountGbp: amountGbp,
        amountIdr: amountIdr,
        currencyCode: currencyCode,
        amountForeign: amountForeign,
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
    await OfflineSyncDatabase.queueDeletion('away_day_expenses', id);
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

  Future<bool> set(double idr) async {
    state = idr < 0 ? 0 : idr;
    return _repo.saveBudget(state);
  }
}

final awayDayBudgetProvider = StateNotifierProvider<BudgetNotifier, double>(
    (ref) => BudgetNotifier(ref.watch(awayDayRepositoryProvider)));

// ---------- Mata uang ringkasan ----------

const _summaryCurrencyKey = 'away_day_summary_currency';

class AwayDaySummaryCurrencyNotifier extends StateNotifier<String> {
  AwayDaySummaryCurrencyNotifier() : super(_load());

  static String _load() {
    final raw = HiveService.cache.get(_summaryCurrencyKey);
    if (raw == null || raw.isEmpty) return 'IDR';
    if (supportedCurrencies.containsKey(raw)) return raw;
    return 'IDR'; // ignore unknown
  }

  Future<void> set(String code) async {
    if (!supportedCurrencies.containsKey(code)) return;
    state = code;
    await HiveService.cache.put(_summaryCurrencyKey, code);
  }
}

final awayDaySummaryCurrencyProvider =
    StateNotifierProvider<AwayDaySummaryCurrencyNotifier, String>(
  (ref) => AwayDaySummaryCurrencyNotifier(),
);

final awayDaySummaryProvider = Provider<AwayDaySummary>((ref) {
  final items = ref.watch(awayDayProvider);
  final selected = ref.watch(awayDaySummaryCurrencyProvider);
  final rates = ref.watch(ratesProvider).valueOrNull?.rates;
  return summarizeExpenses(items, selected, rates);
});

// ---------- Jam dunia (rubrik: WIB / WITA / WIT / London) ----------

final awayDayClockZoneProvider =
    StateProvider.autoDispose<String>((ref) => 'WIB');

final awayDayClockCityProvider =
    StateProvider.autoDispose<String?>((ref) => null);

/// Kota Indonesia yang dipilih untuk menampilkan waktu surya lokalnya.
final awayDayClockIndoCityProvider =
    StateProvider.autoDispose<String?>((ref) => null);

/// Semua klub Premier League basing di Inggris, jadi zona yang relevan adalah
/// WIB, WITA, WIT, dan London (Europe/London, DST ikut dihitung oleh TimeUtils).
///
/// Kunci 'UTC' menyimpan momen UTC mentah supaya perhitungan waktu surya lokal
/// (berbasis bujur) bisa memakai acuan yang sama.
final worldClockProvider =
    StreamProvider.autoDispose<Map<String, DateTime>>((ref) async* {
  while (true) {
    final utc = TimeUtils.nowUtc();
    yield {
      'UTC': utc,
      'WIB': TimeUtils.wib(utc),
      'WITA': TimeUtils.wita(utc),
      'WIT': TimeUtils.wit(utc),
      'London': TimeUtils.london(utc),
    };
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Kurs GBP per 1 Rupiah untuk ringkasan (null bila belum pernah ada cache).
final gbpRateProvider = Provider<double?>((ref) {
  final snap = ref.watch(ratesProvider).valueOrNull;
  return snap?.gbpPerIdr;
});
