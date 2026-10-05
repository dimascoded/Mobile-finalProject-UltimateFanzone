import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../auth/presentation/login_screen.dart';
import '../../sos_emergency/presentation/sos_actions.dart';
import '../../sos_emergency/presentation/sos_hold_button.dart';
import '../../sos_emergency/providers/shake_provider.dart';
import '../../sos_emergency/providers/sos_provider.dart';
import '../providers/dashboard_provider.dart';
import 'feedback_tab.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _pages = <Widget>[
    HomeTab(),
    ProfileTab(),
    FeedbackTab(),
    SizedBox.shrink(), // slot Logout (aksi, bukan halaman)
  ];

  static const _titles = <String>[
    'Smart Football Fan',
    'Profil',
    'Saran & Kesan',
    '',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Goyang HP 2x -> dialog konfirmasi SOS.
    ref.listen<AsyncValue<DateTime>>(shakeProvider, (prev, next) {
      next.whenOrNull(data: (_) => showSosConfirm(context, ref));
    });
    // Hasil SOS dari mana pun (FAB, goyang, layar SOS) -> snackbar.
    ref.listen<AsyncValue<String?>>(sosProvider, (prev, next) {
      next.whenOrNull(
        data: (m) {
          if (m != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
          }
        },
        error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal membaca lokasi: '
                '${e.toString().replaceFirst('Exception: ', '')}'))),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[index]),
        actions: [
          IconButton(
            tooltip: isDark ? 'Mode terang' : 'Mode gelap',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .set(isDark ? ThemeMode.light : ThemeMode.dark),
          ),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),
        // UI2: IndexedStack menyimpan semua tab di tree yang sama. Dengan
        // `_pages[index]` saja, pindah tab membuang state sehingga isian Saran
        // dan Kesan yang diketik hilang begitu user berpindah tab.
        Expanded(
          child: IndexedStack(index: index, children: _pages),
        ),
      ]),
      floatingActionButton: SosHoldButton(
        size: 64,
        onTriggered: () => ref.read(sosProvider.notifier).trigger(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) async {
          if (i == 3) {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Keluar?'),
                content: const Text('Sesi akan dihapus dari perangkat ini.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Keluar')),
                ],
              ),
            );
            if (ok != true) return;
            await ref.read(logoutProvider)();
            if (!context.mounted) return;
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()));
            return;
          }
          ref.read(tabIndexProvider.notifier).state = i;
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
          BottomNavigationBarItem(icon: Icon(Icons.feedback), label: 'Saran'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Logout'),
        ],
      ),
    );
  }
}
