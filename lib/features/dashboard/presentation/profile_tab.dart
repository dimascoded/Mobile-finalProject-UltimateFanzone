import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/auto_lock_observer.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import 'widgets/profile_header.dart';
import 'widgets/profile_sections.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(userEmailProvider);
    final photo = ref.watch(profilePhotoProvider);
    final displayName = email.valueOrNull
            ?.split('@')
            .first
            .replaceAll(RegExp(r'[._-]+'), ' ')
            .trim() ??
        '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              ProfileHeader(
                email: email,
                photoPath: photo,
                onChoosePhoto: () => _choosePhoto(context, ref),
                displayName: displayName,
              ),
              const SizedBox(height: AppSpacing.xl),
              const ProfileStats(),
              const SizedBox(height: AppSpacing.xl),
              const ProfileSections(),
            ],
          ),
        ),
      ],
    );
  }
}
