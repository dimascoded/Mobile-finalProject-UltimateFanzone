import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../trip/data/models.dart';
import '../../trip/providers/trip_providers.dart';
import '../data/itinerary_repository.dart';

class ItineraryNotifier extends StateNotifier<AsyncValue<ItineraryResult?>> {
  ItineraryNotifier(this._repo, String? countryId)
      : super(AsyncData(_repo.cached(countryId)));
  final ItineraryRepository _repo;

  Future<void> generate(Country country, Trip trip) async {
    state = const AsyncLoading();
    try {
      final r = await _repo.generate(country, trip);
      if (mounted) state = AsyncData(r);
    } catch (e, st) {
      // Offline / error API -> tampilkan data terakhir (per negara) dari Hive.
      final cache = _repo.cached(country.id);
      if (mounted) state = cache != null ? AsyncData(cache) : AsyncError(e, st);
    }
  }
}

final itineraryProvider =
    StateNotifierProvider<ItineraryNotifier, AsyncValue<ItineraryResult?>>((ref) {
  final trip = ref.watch(tripProvider);
  return ItineraryNotifier(ref.watch(itineraryRepositoryProvider), trip?.countryId);
});
