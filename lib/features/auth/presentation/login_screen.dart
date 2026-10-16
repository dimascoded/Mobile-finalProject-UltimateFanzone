import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.sports_soccer, size: 80),
              const SizedBox(height: 8),
              Text('Ultimate Fanzone',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading
                      ? null
                      : () => ref
                          .read(authProvider.notifier)
                          .login(_email.text, _password.text),
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Masuk'),
                ),
              ),
              if (biometricEnabled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: loading
                      ? null
                      : () =>
                          ref.read(authProvider.notifier).loginWithBiometric(),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Masuk dengan Biometrik'),
                ),
              ],
              const SizedBox(height: 4),
              // U1: tanpa ini tidak ada cara membuat akun dari aplikasi.
              TextButton(
                onPressed: loading
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        )),
                child: const Text('Belum punya akun? Daftar'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
