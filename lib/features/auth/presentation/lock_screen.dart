import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Tampil saat sesi masih valid: minta biometrik sebelum masuk Dashboard.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider.notifier).unlock());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(authProvider, (prev, next) {
      next.whenOrNull(
        data: (ok) {
          if (ok) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }
        },
        // U2: kalimat Indonesia, bukan `PlatformException` mentah.
        error: (e, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeAuthError(e)))),
      );
    });
    final loading = ref.watch(authProvider).isLoading;
    final biometricEnabled = ref.watch(biometricEnabledProvider);

    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock, size: 72),
          const SizedBox(height: 16),
          const Text('Aplikasi terkunci'),
          const SizedBox(height: 24),
          if (biometricEnabled)
            FilledButton.icon(
              onPressed: loading
                  ? null
                  : () => ref.read(authProvider.notifier).unlock(),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Buka dengan Biometrik'),
            ),
          TextButton(
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
            child: const Text('Gunakan password'),
          ),
        ]),
      ),
    );
  }
}
