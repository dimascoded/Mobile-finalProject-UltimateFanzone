import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/presentation/auto_lock_observer.dart';
import '../../auth/presentation/logout_flow.dart';
import '../../auth/providers/auth_provider.dart';
import '../../football/data/reminder_leads.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/presentation/reminder_settings_screen.dart';
import '../../football/presentation/team_picker_screen.dart';
import '../../football/providers/football_providers.dart';
import '../../football/providers/kickoff_reminder_provider.dart';
import '../../gamification/presentation/card_collection_screen.dart';
import '../../gamification/providers/card_collection_provider.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/dashboard_provider.dart';
import 'feedback_screen.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  Future<void> _choosePhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Kamera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Galeri'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source != null) {
      await withoutAutoLock(
        ref,
        () => ref.read(profilePhotoProvider.notifier).pick(source),
      );
    }
  }

  /// Ringkasan status sinkronisasi untuk kartu di Profil.
  static String _syncSubtitle(SyncState sync, DateTime? lastSync) {
    if (!AppConfig.supabaseConfigured) return 'Cloud belum dikonfigurasi';
    final teks = lastSync == null
        ? 'Otomatis saat ada internet.'
        : 'Otomatis saat ada internet. Terakhir: '
            '${_two(lastSync.hour)}:${_two(lastSync.minute)}';
    if (sync.busy) return 'Mengirim data ke server...';
    if (sync.error != null) return 'Gagal: ${sync.error}';
    final r = sync.result;
    if (r == null) return teks;
    var pesan = '$teks • naik: ${r.pushedExpenses} pengeluaran, '
        '${r.pushedChain} catatan, ${r.pushedPredictions} prediksi';
    if (r.adoptedChain) {
      pesan += ' • Riwayat dipulihkan dari cloud';
      if (r.droppedLocalBlocks > 0) {
        pesan +=
            ' (${r.droppedLocalBlocks} catatan lokal tidak bisa digabung)';
      }
    }
    return pesan;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(userEmailProvider);
    final photo = ref.watch(profilePhotoProvider);
    final stamps = ref.watch(stampsProvider);
    final chain = ref.watch(chainProvider);
    final valid = ref.watch(chainValidProvider);
    final sync = ref.watch(syncProvider);
    final lastSync = ref.watch(lastSyncedAtProvider);
    final favoriteClub = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final ownedClubs = ref.watch(ownedClubsProvider);
    final kickoffLeads = ref.watch(kickoffLeadsProvider);
    final achievements = chain.where((b) => b.type == 'achievement').length;
    final displayName = email.valueOrNull
            ?.split('@')
            .first
            .replaceAll(RegExp(r'[._-]+'), ' ')
            .trim() ??
        '';

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _choosePhoto(context, ref),
                    child: Semantics(
                      button: true,
                      label: 'Ganti foto profil',
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _ProfileAvatar(path: photo),
                          const CircleAvatar(
                            radius: 16,
                            child: Icon(Icons.edit, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isEmpty ? 'Profil saya' : displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        email.when(
                          data: (value) => Text(
                            value ?? '-',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, _) => Text('Gagal memuat: $e'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TeamPickerScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      favoriteClub == null
                          ? CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              child: const Icon(Icons.shield_outlined),
                            )
                          : ClubCrest(
                              crestUrl: crests[favoriteClub.tla.toUpperCase()],
                              tla: favoriteClub.tla,
                              color: favoriteClub.colorValue,
                              size: 40,
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Klub favorit',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              favoriteClub?.name ?? 'Pilih klub favorit',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (favoriteClub != null)
                              Text(
                                '${favoriteClub.stadium} • ${favoriteClub.city}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.style_outlined),
          title: Text('Koleksi Kartu (${ownedClubs.length})'),
          subtitle: const Text('Klub yang sudah kamu kumpulkan'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CardCollectionScreen(),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: Icon(valid ? Icons.verified : Icons.error,
              color: valid ? Colors.green : Colors.red),
          title: const Text('Paspor Suporter'),
          subtitle: Text('${stamps.length} stamp • $achievements pencapaian • '
              '${chain.length} catatan'),
        ),
      ),
      Card(
        child: ListTile(
          leading: sync.busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          title: const Text('Cadangan ke Cloud'),
          subtitle: Text(_syncSubtitle(sync, lastSync)),
          trailing: TextButton(
            onPressed:
                sync.busy ? null : () => ref.read(syncProvider.notifier).run(),
            child: const Text('Cadangkan sekarang'),
          ),
        ),
      ),
      Card(
        child: SwitchListTile.adaptive(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Biometrik'),
          subtitle: const Text('Gunakan sidik jari saat membuka aplikasi'),
          value: biometricEnabled,
          onChanged: (enabled) =>
              ref.read(biometricEnabledProvider.notifier).setEnabled(enabled),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Pengingat Kickoff'),
          subtitle: Text(
            kickoffLeads.isEmpty
                ? 'Mati'
                : kickoffLeads.map(formatLead).join(', '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ReminderSettingsScreen(),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Kesan & Pesan'),
          subtitle: const Text('Mata Kuliah Pemrograman Aplikasi Mobile'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FeedbackScreen()),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Stamp', style: Theme.of(context).textTheme.titleMedium),
      if (stamps.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
              'Belum ada stamp. Kunjungi stadion lewat menu Paspor Suporter.'),
        ),
      for (final b in stamps)
        ListTile(
          leading: const Icon(Icons.approval, color: Colors.teal),
          title: Text('${b.data['stadium']}'),
          subtitle: Text(
              'Catatan #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}'),
        ),
      Card(
        child: ListTile(
          leading: Icon(
            Icons.logout,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Keluar'),
          subtitle: const Text('Hapus sesi dari perangkat ini'),
          onTap: () => confirmAndLogout(context, ref),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Ultimate Fanzone tidak berafiliasi dengan Premier League maupun klub '
        'mana pun. Data pertandingan dari football-data.org.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    ]);
  }
}

/// UI8: `File(path).existsSync()` dipanggil di dalam `build()`, jadi setiap
/// frame membangun ulang (mis. saat provider berubah) menyentuh storage
/// sinkron. Dicek sekali lewat FutureBuilder; kalau file hilang, avatar
/// kembali ke ikon orang.
class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({this.path});

  final String? path;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  Future<bool>? _exists;

  @override
  void didUpdateWidget(_ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _exists = null;
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    if (path == null) {
      return const CircleAvatar(
        radius: 56,
        child: Icon(Icons.person, size: 56),
      );
    }
    final exists = _exists ??= File(path).exists();
    return FutureBuilder<bool>(
      future: exists,
      builder: (context, snap) {
        final ok = snap.data ?? false;
        return CircleAvatar(
          radius: 56,
          backgroundImage: ok ? FileImage(File(path)) : null,
          child: ok ? null : const Icon(Icons.person, size: 56),
        );
      },
    );
  }
}
