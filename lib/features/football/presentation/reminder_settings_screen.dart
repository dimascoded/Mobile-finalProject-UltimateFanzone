import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/section_header.dart';
import '../data/reminder_leads.dart';
import '../providers/football_providers.dart';
import '../providers/kickoff_reminder_provider.dart';

/// Pilihan cepat lead time pengingat (menit) beserta labelnya.
const _presets = <(int, String)>[
  (15, '15 menit'),
  (30, '30 menit'),
  (60, '1 jam'),
  (180, '3 jam'),
  (1440, '1 hari'),
];

// STRUKTUR UI — ReminderSettingsScreen
// Ukuran: Scaffold > Center > ConstrainedBox(maxWidth 720) > ListView.
// [1] Teks pengantar  — penjelasan singkat bahwa maksimal tiga pengingat
// [2] Pengingatmu     — AppCard berisi InputChip untuk lead time aktif, atau
//                        teks "Pengingat dimatikan" bila kosong
// [3] Pilihan cepat   — AppCard berisi FilterChip preset 15 menit sampai
//                        1 hari, terpilih bila sudah aktif
// [4] Tindakan manual — tombol tambah sendiri (buka dialog) dan kembalikan
//                        ke bawaan, catatan batasan, serta peringatan bila
//                        klub favorit belum dipilih
// [5] _AddReminderDialog — dialog jumlah dan satuan (menit/jam/hari) dengan
//                        validasi nilai positif dan batas 7 hari
// Tabel/kolom: tanpa tabel; daftar chip satu kolom terbungkus.
// Sumber data: kickoffLeadsProvider, favoriteClubProvider.
class ReminderSettingsScreen extends ConsumerWidget {
  const ReminderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(kickoffLeadsProvider);
    final favoriteClub = ref.watch(favoriteClubProvider);
    final theme = Theme.of(context);

    void toggle(int minutes) {
      final notifier = ref.read(kickoffLeadsProvider.notifier);
      if (leads.contains(minutes)) {
        notifier.remove(minutes);
        return;
      }
      if (leads.length >= maxReminderSlots) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 3 pengingat.')),
        );
        return;
      }
      notifier.add(minutes);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pengingat Kickoff')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                'Pilih kapan kamu diingatkan sebelum laga timmu mulai. '
                'Maksimal 3 pengingat.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Pengingatmu'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: leads.isEmpty
                    ? Text(
                        'Pengingat dimatikan',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final minutes in leads)
                            InputChip(
                              label: Text(formatLead(minutes)),
                              onDeleted: () => ref
                                  .read(kickoffLeadsProvider.notifier)
                                  .remove(minutes),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Pilihan cepat'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (minutes, label) in _presets)
                      FilterChip(
                        label: Text(label),
                        selected: leads.contains(minutes),
                        onSelected: (_) => toggle(minutes),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _AddReminderDialog(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah sendiri'),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      ref.read(kickoffLeadsProvider.notifier).reset(),
                  child: const Text('Kembalikan ke bawaan'),
                ),
              ),
              const Divider(height: 32),
              Text(
                'Hanya untuk laga tim favoritmu. Pengingat yang waktunya sudah '
                'lewat dilewati.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (favoriteClub == null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Pilih tim favorit di Profil agar pengingat aktif.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddReminderDialog extends ConsumerStatefulWidget {
  const _AddReminderDialog();

  @override
  ConsumerState<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends ConsumerState<_AddReminderDialog> {
  final _controller = TextEditingController();
  String _unit = 'jam';
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_controller.text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Isi angka lebih dari 0.');
      return;
    }
    final minutes = leadFromInput(value, _unit);
    if (minutes <= 0 || minutes > maxLeadMinutes) {
      setState(() => _error = 'Maksimal 7 hari.');
      return;
    }
    ref.read(kickoffLeadsProvider.notifier).add(minutes);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah pengingat'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('reminder-value'),
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              labelText: 'Jumlah',
              counterText: '',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: const Key('reminder-unit'),
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Satuan'),
            items: const [
              DropdownMenuItem(value: 'menit', child: Text('menit')),
              DropdownMenuItem(value: 'jam', child: Text('jam')),
              DropdownMenuItem(value: 'hari', child: Text('hari')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _unit = value;
                _error = null;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
