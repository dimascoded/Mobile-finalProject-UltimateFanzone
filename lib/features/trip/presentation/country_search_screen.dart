import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models.dart';
import '../providers/trip_providers.dart';

class CountrySearchScreen extends ConsumerWidget {
  const CountrySearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(filteredCountriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Negara Tujuan')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => ref.read(countryQueryProvider.notifier).state = v,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Cari negara atau mata uang',
            ),
          ),
        ),
        Expanded(
          child: countries.when(
            data: (list) => list.isEmpty
                ? const Center(child: Text('Negara tidak ditemukan'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: Text(c.flag, style: const TextStyle(fontSize: 32)),
                        title: Text(c.name),
                        subtitle: Text('${c.currency} • ${c.tzLabel}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openForm(context, ref, c),
                      );
                    },
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Gagal memuat data: $e')),
          ),
        ),
      ]),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref, Country c) async {
    final trip = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TripForm(country: c),
    );
    if (trip == null) return;
    await ref.read(tripProvider.notifier).setTrip(trip);
    if (context.mounted) Navigator.pop(context);
  }
}

class _TripForm extends StatefulWidget {
  const _TripForm({required this.country});
  final Country country;
  @override
  State<_TripForm> createState() => _TripFormState();
}

class _TripFormState extends State<_TripForm> {
  final _city = TextEditingController();
  final _budget = TextEditingController();
  int _days = 3;

  @override
  void dispose() {
    _city.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.country;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${c.flag} ${c.name}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _city,
          decoration: const InputDecoration(
              labelText: 'Kota (opsional, mis. Tokyo)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Anggaran (Rp, opsional)'),
        ),
        Row(children: [
          const Text('Durasi'),
          Expanded(
            child: Slider(
              value: _days.toDouble(),
              min: 1,
              max: 14,
              divisions: 13,
              label: '$_days hari',
              onChanged: (v) => setState(() => _days = v.round()),
            ),
          ),
          Text('$_days hari'),
        ]),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              Trip(
                countryId: c.id,
                city: _city.text.trim(),
                days: _days,
                budgetIdr: double.tryParse(_budget.text) ?? 0,
              ),
            ),
            child: const Text('Mulai Trip'),
          ),
        ),
      ]),
    );
  }
}
