import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/time_utils.dart';
import '../providers/trip_providers.dart';
import 'country_search_screen.dart';

class TripCard extends ConsumerWidget {
  const TripCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    final country = ref.watch(activeCountryProvider);
    final clock = ref.watch(destinationClockProvider);
    void open() => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const CountrySearchScreen()));

    if (trip == null || country == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.flight_takeoff, size: 36),
          title: const Text('Mulai perjalanan'),
          subtitle: const Text('Pilih negara tujuan untuk mengaktifkan semua fitur'),
          trailing: FilledButton(onPressed: open, child: const Text('Pilih')),
        ),
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Text(country.flag, style: const TextStyle(fontSize: 44)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                trip.city.isEmpty ? country.name : '${trip.city}, ${country.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('${trip.days} hari • ${country.currency}'),
              clock.when(
                data: (t) => Text(
                  t == null ? '-' : 'Waktu lokal ${TimeUtils.format(t)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                loading: () => const Text('...'),
                error: (e, _) => Text('$e'),
              ),
            ]),
          ),
          IconButton(onPressed: open, icon: const Icon(Icons.edit)),
        ]),
      ),
    );
  }
}
