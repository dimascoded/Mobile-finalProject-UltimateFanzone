import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/section_header.dart';
import '../data/reminder_leads.dart';
import '../providers/football_providers.dart';
import '../providers/kickoff_reminder_provider.dart';

// STRUKTUR UI — ReminderSettingsScreen
// Ukuran: Scaffold > Center > ConstrainedBox(maxWidth 720) > ListView.
// [1] Teks pengantar  — penjelasan singkat bahwa maksimal tiga pengingat
// [2] Pengingatmu     — AppCard berisi InputChip untuk lead time aktif, atau
//                        teks "Pengingat dimatikan" bila kosong
// [3] Tambah pengingat — AppCard dengan tiga kolom Hari/Jam/Menit + preview
//                        + tombol Tambah; penyimpanan lewat kickoffLeadsProvider
// Sumber data: kickoffLeadsProvider, favoriteClubProvider.
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState
    extends ConsumerState<ReminderSettingsScreen> {
  final _daysController = TextEditingController();
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return 0;
    return int.tryParse(text) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(kickoffLeadsProvider);
    final favoriteClub = ref.watch(favoriteClubProvider);
    final theme = Theme.of(context);

    final days = _parse(_daysController);
    final hours = _parse(_hoursController);
    final minutes = _parse(_minutesController);
    final total = leadFromDhm(days, hours, minutes);
    final preview = total > 0 ? formatLead(total) : null;
    final canAdd = total > 0;
    final overLimit = total > maxLeadMinutes;
    String? errorText;
    if (overLimit) {
      errorText = 'Maksimal 7 hari.';
    }

    void addReminder() {
      if (!canAdd || overLimit) return;
      if (leads.length >= maxReminderSlots) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 3 pengingat.')),
        );
        return;
      }
      if (leads.contains(total)) return;
      ref.read(kickoffLeadsProvider.notifier).add(total);
      _daysController.clear();
      _hoursController.clear();
      _minutesController.clear();
      setState(() {});
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
                'Pilih kapan kamu diingatkan sebelum laga mulai. '
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
                          for (final minutesLead in leads)
                            InputChip(
                              label: Text(formatLead(minutesLead)),
                              onDeleted: () => ref
                                  .read(kickoffLeadsProvider.notifier)
                                  .remove(minutesLead),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Tambah pengingat'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('reminder-days'),
                            controller: _daysController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(1),
                            ],
                            decoration: const InputDecoration(labelText: 'Hari'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            key: const Key('reminder-hours'),
                            controller: _hoursController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(labelText: 'Jam'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextField(
                            key: const Key('reminder-minutes'),
                            controller: _minutesController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: const InputDecoration(labelText: 'Menit'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (preview != null)
                      Text(
                        '= $preview',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          errorText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        key: const Key('reminder-add'),
                        onPressed: canAdd && !overLimit ? addReminder : null,
                        child: const Text('Tambah'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
                'Berlaku untuk laga terdekat di liga dan semua laga tim '
                'favoritmu. Pengingat yang waktunya sudah lewat dilewati.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (favoriteClub == null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Pilih tim favorit di Profil agar semua laganya selalu '
                  'diingatkan.',
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
