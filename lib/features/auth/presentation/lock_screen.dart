import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/scrim_image.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'auto_lock_observer.dart';
import 'logout_flow.dart';

// STRUKTUR UI — LockScreen
// Ukuran: PopScope > Scaffold > Stack: ScrimImage latar + SafeArea >
//         SingleChildScrollView > ConstrainedBox(maxWidth 420).
// [1] Ikon kunci      — bundar 88px berisi ikon lock di atas latar gelap
// [2] Judul           — teks "Aplikasi terkunci" di tengah
// [3] AppCard aksi    — tombol biometrik (bila aktif), tombol password, dan
//                        tombol keluar dari akun
// [4] _PasswordDialog — dialog password tersembunyi; verifikasi lewat
//                        AuthRepository.verifyPassword tanpa mengakhiri sesi
// Tabel/kolom: tanpa tabel; satu kolom aksi pada layar kunci.
// Sumber data: authProvider, biometricEnabledProvider.
/// Tampil saat sesi masih valid: minta biometrik sebelum masuk Dashboard.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, this.popOnSuccess = false});

  /// true = didorong di atas Dashboard (auto-lock) dan cukup `pop` begitu
  /// terbuka, supaya pengguna kembali ke tab yang sama. false = layar awal.
  final bool popOnSuccess;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          withoutAutoLock(ref, () => ref.read(authProvider.notifier).unlock()),
    );
  }

  void _onUnlocked() {
    if (!mounted) return;
    if (widget.popOnSuccess) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  Future<void> _unlockWithBiometric() => withoutAutoLock(
        ref,
        () => ref.read(authProvider.notifier).unlock(),
      );

  Future<void> _showPasswordDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (ok == true) _onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(authProvider, (prev, next) {
      next.whenOrNull(
        data: (ok) {
          if (ok) _onUnlocked();
        },
        // U2: kalimat Indonesia, bukan `PlatformException` mentah.
        error: (e, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeAuthError(e)))),
      );
    });
    final loading = ref.watch(authProvider).isLoading;
    final biometricEnabled = ref.watch(biometricEnabledProvider);
    final theme = Theme.of(context);
    final fz = context.fz;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ScrimImage(
              assetPath: AppImages.bgLogin,
              borderRadius: 0,
              scrim: 0.7,
              showPitchPattern: true,
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fz.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.lock, size: 44, color: fz.onAccent),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Aplikasi terkunci',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (biometricEnabled)
                                FilledButton.icon(
                                  onPressed:
                                      loading ? null : _unlockWithBiometric,
                                  icon: const Icon(Icons.fingerprint),
                                  label: const Text('Buka dengan Biometrik'),
                                ),
                              TextButton(
                                onPressed: loading ? null : _showPasswordDialog,
                                child: const Text('Gunakan password'),
                              ),
                              TextButton(
                                onPressed: loading
                                    ? null
                                    : () => confirmAndLogout(context, ref),
                                child: const Text('Keluar dari akun'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog password untuk membuka layar kunci. Mengembalikan `true` lewat
/// `Navigator.pop` bila verifikasi berhasil.
///
/// Verifikasi memakai [AuthRepository.verifyPassword] dan TIDAK mengakhiri
/// sesi, jadi data pengguna tetap utuh walau password salah.
class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyPassword(_controller.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeAuthError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masuk dengan password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Buka'),
        ),
      ],
    );
  }
}
