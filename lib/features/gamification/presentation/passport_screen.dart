import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/pill_badge.dart';
import '../../../core/ui/scrim_image.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/settings_section.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/presentation/team_picker_screen.dart';
import '../../football/providers/football_providers.dart';
import '../providers/card_collection_provider.dart';
import '../providers/gamification_providers.dart';
import 'card_collection_screen.dart';

// STRUKTUR UI — PassportScreen
// Ukuran: Scaffold + AppBar, body ListView satu kolom tanpa batas lebar;
// header ScrimImage setinggi 190 * textScale
// [1] Empty state — kolom "Pilih tim favorit dulu" plus tombol menuju TeamPickerScreen
// [2] Header klub — ScrimImage: crest, nama klub, stadion dan kota, PillBadge jarak ke stadion
// [3] Kartu aksi cap — info radius cap, tombol "Cap stamp", switch mode demo
// [4] Status riwayat — SettingsTile validitas rantai catatan
// [5] Kartu Koleksi Kartu — ListTile jumlah kartu dan jumlah klub terkumpul
// [6] Daftar stamp stadion — SectionHeader lalu kartu kosong atau AppCard per catatan stamp
// Tabel/kolom: tanpa tabel; daftar stamp satu kolom (satu ListTile per catatan)
// Sumber data: favoriteClubProvider, clubCrestProvider, stampsProvider, chainValidProvider,
// demoModeProvider, stampProvider, stampDistanceProvider, cardCollectionProvider, ownedClubsProvider

class PassportScreen extends ConsumerWidget {
  const PassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(stampProvider, (previous, next) {
      next.whenOrNull(
        data: (message) {
          if (message != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
        error: (error, _) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error.toString().replaceFirst('Exception: ', '')),
              ),
            );
          }
        },
      );
    });
    final club = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final stamps = ref.watch(stampsProvider);
    final valid = ref.watch(chainValidProvider);
    final demoMode = ref.watch(demoModeProvider);
    final busy = ref.watch(stampProvider).isLoading;
    final distance = ref.watch(stampDistanceProvider);
    if (club == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paspor Suporter')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pilih tim favorit dulu'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TeamPickerScreen(),
                  ),
                ),
                child: const Text('Pilih tim'),
              ),
            ],
          ),
        ),
      );
    }

    final textScaler =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final headerHeight = 190.0 * textScaler;

    return Scaffold(
      appBar: AppBar(title: const Text('Paspor Suporter')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ScrimImage(
            assetPath: AppImages.headerLaga,
            height: headerHeight,
            scrim: 0.75,
            showPitchPattern: true,
            borderRadius: AppRadius.xl,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClubCrest(
                          crestUrl: crests[club.tla.toUpperCase()],
                          tla: club.tla,
                          color: club.colorValue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          club.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${club.stadium} • ${club.city}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PillBadge(
                    label: distance.when(
                      loading: () => 'Mengukur jarak ke stadion\u2026',
                      data: (m) {
                        if (m == null) {
                          return 'Jarak tidak diukur '
                              '(GPS mati atau izin belum diberikan).';
                        }
                        return 'Anda $m m dari ${club.stadium}.'
                            '${m <= stampRadiusMeters.round() ? ' Dalam jangkauan!' : ' Terlalu jauh untuk cap GPS.'}';
                      },
                      error: (e, _) =>
                          'Gagal mengukur jarak: ${e.toString().replaceFirst('Exception: ', '')}',
                    ),
                    tone: distance.when(
                      loading: () => PillTone.neutral,
                      data: (m) {
                        if (m == null || m > stampRadiusMeters.round()) {
                          return PillTone.neutral;
                        }
                        return PillTone.accent;
                      },
                      error: (_, __) => PillTone.neutral,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        demoMode
                            ? 'Mode demo aktif, GPS dilewati.'
                            : 'Cap tersedia dalam radius '
                                '${stampRadiusMeters.round()} m dari stadion.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (!demoMode)
                      IconButton(
                        tooltip: 'Perbarui jarak',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.invalidate(stampDistanceProvider),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!demoMode) {
                              final allowed = await confirmPermission(
                                context,
                                ref,
                                permissionKey: 'location',
                                title: 'Izin lokasi untuk cap stadion',
                                message:
                                    'Lokasi digunakan untuk memeriksa jarak Anda dari stadion ${club.stadium}.',
                              );
                              if (!allowed || !context.mounted) return;
                            }
                            await ref.read(stampProvider.notifier).stamp(club);
                          },
                    child: busy
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Text('Mencetak\u2026'),
                            ],
                          )
                        : const Text('Cap stamp'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode demo'),
                  subtitle: Text(
                    'Melewati pemeriksaan GPS',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: demoMode,
                  onChanged: (enabled) {
                    ref.read(demoModeProvider.notifier).state = enabled;
                    if (enabled) ref.invalidate(stampDistanceProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsTile(
            icon: Icon(valid ? Icons.verified : Icons.error),
            title: valid ? 'Riwayat aman' : 'Riwayat tidak cocok',
            subtitle: valid
                ? 'Semua pencapaianmu tercatat dan belum pernah diubah.'
                : 'Ada catatan yang tidak sesuai. Coba cadangkan ulang.',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardCollectionScreen(),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.style_outlined),
              title: Text(
                  'Koleksi Kartu (${ref.watch(cardCollectionProvider).length})'),
              subtitle: Text(
                  '${ref.watch(ownedClubsProvider).length} klub terkumpul'),
              trailing: const Icon(Icons.chevron_right),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: 'Stamp stadion ${club.name}'),
          const SizedBox(height: AppSpacing.md),
          if (stamps.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Belum ada stamp. Buka GPS lalu cap stadion favoritmu.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...stamps.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.approval,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text('${b.data['stadium']}'),
                    subtitle: Text(
                      'Catatan #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}',
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
