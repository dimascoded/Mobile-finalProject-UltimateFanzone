import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../data/auth_repository.dart';
import '../providers/auth_provider.dart';

/// U1: layar pendaftaran akun baru.
///
/// Password di-hash SHA-256 di [AuthRepository.register] sebelum dikirim, jadi
/// yang tampil di sini hanya kolom kosong; tidak ada log atau cache yang
/// menyimpan password mentah.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
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
        // U2: pesan error sudah Bahasa Indonesia, bukan `DioException` mentah.
        error: (e, _) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeAuthError(e)))),
      );
    });

    final loading = ref.watch(authProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Akun')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      helperText: 'Dipakai untuk masuk dan sinkronisasi data',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'Minimal 8 karakter',
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: 'Ulangi password',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: loading
                          ? null
                          : () => ref.read(authProvider.notifier).register(
                                _email.text,
                                _password.text,
                                _confirm.text,
                              ),
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Daftar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed:
                        loading ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Sudah punya akun? Masuk'),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}
