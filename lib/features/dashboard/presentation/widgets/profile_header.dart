import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_images.dart';
import '../../../../core/ui/scrim_image.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/presentation/team_picker_screen.dart';
import '../../../football/providers/football_providers.dart';

class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    required this.email,
    required this.photoPath,
    required this.onChoosePhoto,
    required this.displayName,
  });

  final AsyncValue<String?> email;
  final String? photoPath;
  final VoidCallback onChoosePhoto;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteClub = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final textScaler =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final height = 230.0 * textScaler;

    return Column(
      children: [
        ScrimImage(
          assetPath: AppImages.headerLaga,
          height: height,
          scrim: 0.75,
          showPitchPattern: true,
          borderRadius: AppRadius.xl,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onChoosePhoto,
                  child: Semantics(
                    button: true,
                    label: 'Ganti foto profil',
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        _ProfileAvatar(path: photoPath),
                        const CircleAvatar(
                          radius: 16,
                          child: Icon(Icons.edit, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  displayName.isEmpty ? 'Profil saya' : displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                email.when(
                  data: (value) => Text(
                    value ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    'Gagal memuat: $e',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TeamPickerScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        favoriteClub == null
                            ? const CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: Colors.black87,
                                ),
                              )
                            : ClubCrest(
                                crestUrl:
                                    crests[favoriteClub.tla.toUpperCase()],
                                tla: favoriteClub.tla,
                                color: favoriteClub.colorValue,
                                size: 24,
                              ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            favoriteClub?.name ?? 'Pilih klub favorit',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
      return CircleAvatar(
        radius: 40,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        child: const Icon(
          Icons.person,
          size: 44,
          color: Colors.white,
        ),
      );
    }
    final exists = _exists ??= File(path).exists();
    return FutureBuilder<bool>(
      future: exists,
      builder: (context, snap) {
        final ok = snap.data ?? false;
        return CircleAvatar(
          radius: 40,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: ok ? FileImage(File(path)) : null,
          child: ok
              ? null
              : const Icon(
                  Icons.person,
                  size: 44,
                  color: Colors.white,
                ),
        );
      },
    );
  }
}
