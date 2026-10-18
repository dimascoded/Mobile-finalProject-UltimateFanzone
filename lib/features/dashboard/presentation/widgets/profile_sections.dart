import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/settings_section.dart';
import '../../../../core/ui/stat_tile.dart';
import '../../../../core/utils/app_config.dart';
import '../../../auth/presentation/logout_flow.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../football/data/reminder_leads.dart';
import '../../../football/presentation/reminder_settings_screen.dart';
import '../../../football/providers/kickoff_reminder_provider.dart';
import '../../../gamification/presentation/card_collection_screen.dart';
import '../../../gamification/presentation/passport_screen.dart';
import '../../../gamification/providers/card_collection_provider.dart';
import '../../../gamification/providers/gamification_providers.dart';
import '../../../sync/providers/sync_provider.dart';
import '../feedback_screen.dart';

/// Ringkasan status sinkronisasi untuk kartu di Profil.
String syncSubtitle(SyncState sync, DateTime? lastSync) {
  if (!AppConfig.supabaseConfigured) return 'Cloud belum dikonfigurasi';
  final teks = lastSync == null
      ? 'Otomatis saat ada internet.'
      : 'Otomatis saat ada internet. Terakhir: '
          '${_two(lastSync.hour)}:${_two(lastSync.minute)}';
  if (sync.busy) return 'Mengirim data ke server...';
  if (sync.error != null) return 'Gagal: ${sync.error}';
  final r = sync.result;
  if (r == null) return teks;
  var pesan = '$teks naik: ${r.pushedExpenses} pengeluaran, '
      '${r.pushedChain} catatan, ${r.pushedPredictions} prediksi';
  if (r.adoptedChain) {
    pesan += '  Riwayat dipulihkan dari cloud';
    if (r.droppedLocalBlocks > 0) {
      pesan += ' (${r.droppedLocalBlocks} catatan lokal tidak bisa digabung)';
    }
  }
  return pesan;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Baris ringkasan tiga statistik di atas bagian Profil.
class ProfileStats extends ConsumerWidget {
  const ProfileStats({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stamps = ref.watch(stampsProvider);
    final chain = ref.watch(chainProvider);
    final achievements = chain.where((b) => b.type == 'achievement').length;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            icon: const Icon(Icons.approval_outlined),
            value: '${stamps.length}',
            label: 'Stempel',
            detail: 'PassportScreen',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PassportScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            icon: const Icon(Icons.style_outlined),
            value: '${ref.watch(cardCollectionProvider).length}',
            label: 'Kartu',
            detail: '${ref.watch(ownedClubsProvider).length} klub',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardCollectionScreen(),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatTile(
            icon: const Icon(Icons.emoji_events_outlined),
            value: '$achievements',
            label: 'Pencapaian',
            detail: 'total',
          ),
        ),
      ],
    );
  }
}

/// Bagian-bagian pengaturan di Profil.
class ProfileSections extends ConsumerWidget {
  const ProfileSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stamps = ref.watch(stampsProvider);
    final chain = ref.watch(chainProvider);
    final achievements = chain.where((b) => b.type == 'achievement').length;
    final valid = ref.watch(chainValidProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final kickoffLeads = ref.watch(kickoffLeadsProvider);
    final sync = ref.watch(syncProvider);
    final lastSync = ref.watch(lastSyncedAtProvider);
    return Column(
      children: [
        SettingsSection(
          title: 'Aktivitas',
          children: [
            SettingsTile(
              icon: Icon(valid ? Icons.verified : Icons.error),
              title: 'Paspor Suporter',
              subtitle:
                  '${stamps.length} stamp  $achievements pencapaian  ${chain.length} catatan',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PassportScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: const Icon(Icons.style_outlined),
              title: 'Koleksi Kartu',
              subtitle:
                  '${ref.watch(cardCollectionProvider).length} kartu • ${ref.watch(ownedClubsProvider).length} klub',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CardCollectionScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSection(
          title: 'Keamanan',
          children: [
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Biometrik'),
              subtitle: const Text('Gunakan sidik jari saat membuka aplikasi'),
              value: biometricEnabled,
              onChanged: (enabled) => ref
                  .read(biometricEnabledProvider.notifier)
                  .setEnabled(enabled),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSection(
          title: 'Notifikasi',
          children: [
            SettingsTile(
              icon: const Icon(Icons.notifications_active_outlined),
              title: 'Pengingat Kickoff',
              subtitle: kickoffLeads.isEmpty
                  ? 'Mati'
                  : kickoffLeads.map(formatLead).join(', '),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReminderSettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSection(
          title: 'Data',
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTile(
                  icon: sync.busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  title: 'Cadangan ke Cloud',
                  subtitle: syncSubtitle(sync, lastSync),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 0, AppSpacing.md, AppSpacing.xs),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: sync.busy
                          ? null
                          : () => ref.read(syncProvider.notifier).run(),
                      child: const Text('Cadangkan sekarang'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSection(
          title: 'Tentang',
          children: [
            SettingsTile(
              icon: const Icon(Icons.menu_book_outlined),
              title: 'Kesan & Pesan',
              subtitle: 'Mata Kuliah Pemrograman Aplikasi Mobile',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FeedbackScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ultimate Fanzone tidak berafiliasi dengan Premier League maupun klub '
          'mana pun. Data pertandingan dari football-data.org.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.fz.textMuted,
              ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsSection(
          title: 'Akun',
          children: [
            SettingsTile(
              icon: const Icon(Icons.logout),
              title: 'Keluar',
              subtitle: 'Hapus sesi dari perangkat ini',
              onTap: () => confirmAndLogout(context, ref),
              destructive: true,
            ),
          ],
        ),
      ],
    );
  }
}
