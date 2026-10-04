import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/time_utils.dart';
import '../data/models.dart';
import '../data/trip_repository.dart';

final countriesProvider = FutureProvider<List<Country>>(
    (ref) => ref.watch(countryRepositoryProvider).load());

class TripNotifier extends StateNotifier<Trip?> {
  // Sementara (migrasi ke Smart Football Fan): trip default = Inggris, tujuan Away Day.
  TripNotifier(this._repo) : super(_repo.load() ?? const Trip(countryId: 'GB', days: 3));
  final TripRepository _repo;

  Future<void> setTrip(Trip t) async {
    state = t;
    await _repo.save(t);
  }

  Future<void> clear() async {
    state = null;
    await _repo.clear();
  }
}

final tripProvider = StateNotifierProvider<TripNotifier, Trip?>(
    (ref) => TripNotifier(ref.watch(tripRepositoryProvider)));

/// Negara dari Trip aktif (null jika belum memilih).
final activeCountryProvider = Provider<Country?>((ref) {
  final trip = ref.watch(tripProvider);
  final countries = ref.watch(countriesProvider).valueOrNull;
  if (trip == null || countries == null) return null;
  for (final c in countries) {
    if (c.id == trip.countryId) return c;
  }
  return null;
});

// ---- Pencarian negara ----
final countryQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final filteredCountriesProvider =
    Provider.autoDispose<AsyncValue<List<Country>>>((ref) {
  final q = ref.watch(countryQueryProvider).toLowerCase().trim();
  return ref.watch(countriesProvider).whenData((list) => q.isEmpty
      ? list
      : list
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.currency.toLowerCase().contains(q) ||
              c.id.toLowerCase().contains(q))
          .toList());
});

/// Jam di negara tujuan, update tiap detik (berhenti saat tidak dipakai).
final destinationClockProvider = StreamProvider.autoDispose<DateTime?>((ref) async* {
  final c = ref.watch(activeCountryProvider);
  if (c == null) {
    yield null;
    return;
  }
  while (true) {
    yield TimeUtils.zoneTime(TimeUtils.nowUtc(), c.utcOffset, c.tzRule);
    await Future.delayed(const Duration(seconds: 1));
  }
});
