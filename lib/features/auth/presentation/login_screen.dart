import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/scrim_image.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

// STRUKTUR UI — LoginScreen
// Ukuran: Scaffold > Stack: ScrimImage latar + SafeArea >
//         SingleChildScrollView > ConstrainedBox(maxWidth 420).
// [1] Ikon bola       — bundar 88px berisi ikon sepak bola
// [2] Judul & subjudul — "Ultimate Fanzone" dan tagline teman suporter
// [3] AppCard form    — kolom email, kolom password dengan tombol lihat
//                        sandi, tombol Masuk, tombol Masuk dengan Biometrik
//                        (bila aktif), dan tautan pendaftaran
// Tabel/kolom: tanpa tabel; satu kolom form di dalam kartu.
// Sumber data: authProvider, biometricEnabledProvider.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
        // U2: tampilkan kalimat Indonesia, bukan teks galat mentah.
        error: (e, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeAuthError(e)))),
      );
    });

    final loading = ref.watch(authProvider).isLoading;
    final biometricEnabled = ref.watch(biometricEnabledProvider);

    final theme = Theme.of(context);
    final fz = context.fz;

    return Scaffold(
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
                        child: Icon(Icons.sports_soccer,
                            size: 44, color: fz.onAccent),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Ultimate Fanzone',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Teman suporter Premier League-mu',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            FilledButton(
                              onPressed: loading
                                  ? null
                                  : () => ref
                                      .read(authProvider.notifier)
                                      .login(_email.text, _password.text),
                              child: loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Masuk'),
                            ),
                            if (biometricEnabled) ...[
                              const SizedBox(height: AppSpacing.md),
                              OutlinedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () => ref
                                        .read(authProvider.notifier)
                                        .loginWithBiometric(),
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Masuk dengan Biometrik'),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            // U1: tanpa ini tidak ada cara membuat akun.
                            TextButton(
                              onPressed: loading
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RegisterScreen(),
                                        ),
                                      ),
                              child: const Text('Belum punya akun? Daftar'),
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
    );
  }
}
