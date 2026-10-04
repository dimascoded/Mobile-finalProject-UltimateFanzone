import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/away_day_repository.dart';
import '../providers/away_day_providers.dart';
import '../../football/providers/football_providers.dart';
import '../../../core/network/rates_provider.dart';

class AwayDayScreen extends ConsumerStatefulWidget {
  const AwayDayScreen({super.key});

  @override
  ConsumerState<AwayDayScreen> createState() => _AwayDayScreenState();
}

class _AwayDayScreenState extends ConsumerState<AwayDayScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _gbp = TextEditingController();
  AwayDayCategory _cat = AwayDayCategory.tiket;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(awayDayFilteredProvider);
    final total = ref.watch(awayDayTotalProvider);
    final budget = ref.watch(awayDayBudgetProvider);
    final club = ref.watch(favoriteClubProvider);
    final rates = ref.watch(ratesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Away Day')),
      body: Column(children: [
        if (rates.isLoading)
          const LinearProgressIndicator()
        else if (rates.hasError)
          const Chip(label: Text('Kurs tidak tersedia')),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) => Card(
              child: ListTile(
                title: Text(list[i].title),
                subtitle: Text('${list[i].amountGbp.toStringAsFixed(2)} GBP (Rp ${list[i].amountIdr.toStringAsFixed(0)})'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => ref.read(awayDayProvider.notifier).remove(list[i].id),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Total: Rp ${total.toStringAsFixed(0)} | Anggaran: Rp ${budget.toStringAsFixed(0)}'),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah pengeluaran'),
        content: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Judul'),
              validator: (v) => v?.isEmpty == true ? 'Wajib diisi' : null,
            ),
            TextFormField(
              controller: _gbp,
              decoration: const InputDecoration(labelText: 'Jumlah (GBP)'),
              keyboardType: TextInputType.number,
              validator: (v) => (double.tryParse(v ?? '') == null) ? 'Angka salah' : null,
            ),
            DropdownButtonFormField(
              value: _cat,
              items: AwayDayCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            )
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: _save, child: const Text('Simpan')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final gbp = double.parse(_gbp.text);
    final rates = ref.read(ratesProvider).valueOrNull;
    final gbpRate = rates?['GBP'] ?? 0;
    final idr = gbp * gbpRate;
    final club = ref.read(favoriteClubProvider)?.key;
    await ref.read(awayDayProvider.notifier).add(
          title: _title.text,
          amountGbp: gbp,
          amountIdr: idr,
          category: _cat,
          clubKey: club,
        );
    if (mounted) Navigator.pop(context);
  }
}