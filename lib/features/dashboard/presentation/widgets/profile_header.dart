import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_images.dart';
import '../../../../core/ui/pill_badge.dart';
import '../../../../core/ui/scrim_image.dart';
import '../../../football/presentation/club_crest.dart';
import '../../../football/presentation/team_picker_screen.dart';
import '../../../football/providers/football_providers.dart';
import '../../../prediction/data/prediction_rank.dart';
import '../../../prediction/providers/prediction_provider.dart';
import '../../providers/dashboard_provider.dart';

class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    super.key,
    required this.email,
    required this.photoPath,
    required this.onChoosePhoto,
  });

  final AsyncValue<String?> email;
  final String? photoPath;
  final VoidCallback onChoosePhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteClub = ref.watch(favoriteClubProvider);
    final predictionRank = rankFor(ref.watch(predictionPointsProvider));
    final crests = ref.watch(clubCrestProvider);
    final displayName =
        ref.watch(effectiveDisplayNameProvider).valueOrNull ?? '';
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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: height - 2 * AppSpacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                    Semantics(
                      button: true,
                      label: 'Ubah nama',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _editName(
                          context,
                          ref,
                          displayName.isEmpty ? 'Profil saya' : displayName,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                displayName.isEmpty
                                    ? 'Profil saya'
                                    : displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
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
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
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
                                        crestUrl: crests[
                                            favoriteClub.tla.toUpperCase()],
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
                        PillBadge(
                          label: predictionRank.name,
                          tone: PillTone.accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editName(
      BuildContext context, WidgetRef ref, String current) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditNameDialog(
        initial: current,
        onSave: (raw) => ref.read(displayNameProvider.notifier).set(raw),
      ),
    );
    if (saved == true) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nama diperbarui')),
      );
    }
  }
}

/// Dialog ubah nama tampilan. Miliki sendiri [TextEditingController]-nya
/// supaya controller ikut terbuang bersama widget setelah animasi penutupan
/// selesai (tidak dipakai lagi setelah dispose).
class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initial, required this.onSave});

  final String initial;
  final Future<String?> Function(String raw) onSave;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = await widget.onSave(_controller.text);
    if (err != null) {
      if (mounted) setState(() {});
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final error = validateDisplayName(_controller.text);
    return AlertDialog(
      title: const Text('Ubah nama'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        decoration: InputDecoration(
          hintText: 'Nama tampilan',
          errorText: error,
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: error != null ? null : _save,
          child: const Text('Simpan'),
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
