import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/permission_rationale.dart';

/// Layar penuh: tampilkan penjelasan dulu, baru [child] (yang meminta izin) dibangun.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.permissionKey,
    required this.icon,
    required this.title,
    required this.message,
    required this.child,
  });
  final String permissionKey, title, message;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accepted = ref.watch(permissionRationaleProvider).contains(permissionKey);
    if (accepted) return child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => ref.read(permissionRationaleProvider.notifier).accept(permissionKey),
            child: const Text('Lanjutkan'),
          ),
        ]),
      ),
    );
  }
}

/// Dialog penjelasan satu kali sebelum aksi yang memicu permintaan izin.
Future<bool> confirmPermission(
  BuildContext context,
  WidgetRef ref, {
  required String permissionKey,
  required String title,
  required String message,
}) async {
  if (ref.read(permissionRationaleProvider).contains(permissionKey)) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lanjutkan')),
      ],
    ),
  );
  if (ok != true) return false;
  await ref.read(permissionRationaleProvider.notifier).accept(permissionKey);
  return true;
}
