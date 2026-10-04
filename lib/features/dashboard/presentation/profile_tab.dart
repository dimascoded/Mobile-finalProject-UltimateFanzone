import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/providers/auth_provider.dart';
import '../../gamification/providers/gamification_providers.dart';
import '../providers/dashboard_provider.dart';

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
    if (source != null) await ref.read(profilePhotoProvider.notifier).pick(source);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(userEmailProvider);
    final wallet = ref.watch(walletAddressProvider);
    final photo = ref.watch(profilePhotoProvider);
    final stamps = ref.watch(stampsProvider);
    final chain = ref.watch(chainProvider);
    final valid = ref.watch(chainValidProvider);
    final achievements = chain.where((b) => b.type == 'achievement').length;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: GestureDetector(
          onTap: () => _choosePhoto(context, ref),
          child: Stack(alignment: Alignment.bottomRight, children: [
            CircleAvatar(
              radius: 56,
              backgroundImage: photo != null && File(photo).existsSync()
                  ? FileImage(File(photo))
                  : null,
              child: photo == null ? const Icon(Icons.person, size: 56) : null,
            ),
            const CircleAvatar(radius: 16, child: Icon(Icons.edit, size: 16)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: email.when(
          data: (e) => Text(e ?? '-', style: Theme.of(context).textTheme.titleMedium),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('Gagal memuat: $e'),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.account_balance_wallet),
          title: const Text('Wallet Web3'),
          subtitle: wallet.when(
            data: (a) => SelectableText(a),
            loading: () => const Text('Membuat wallet...'),
            error: (e, _) => Text('Gagal: $e'),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: Icon(valid ? Icons.verified : Icons.error,
              color: valid ? Colors.green : Colors.red),
          title: const Text('Paspor Digital'),
          subtitle: Text('${stamps.length} stamp • $achievements achievement • '
              '${chain.length} blok'),
        ),
      ),
      const SizedBox(height: 8),
      Text('Stamp', style: Theme.of(context).textTheme.titleMedium),
      if (stamps.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada stamp. Kunjungi stadion lewat menu Paspor Digital.'),
        ),
      for (final b in stamps)
        ListTile(
          leading: const Icon(Icons.approval, color: Colors.teal),
          title: Text('${b.data['stadium']}'),
          subtitle: Text(
              'Blok #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}'),
        ),
    ]);
  }
}
