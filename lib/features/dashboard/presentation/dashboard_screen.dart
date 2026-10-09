import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../sos_emergency/presentation/sos_actions.dart';
import '../../sos_emergency/presentation/sos_hold_button.dart';
import '../../sos_emergency/providers/shake_provider.dart';
import '../../sos_emergency/providers/sos_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../providers/dashboard_provider.dart';
import 'home_tab.dart';
import 'profile_tab.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const _pages = <Widget>[
    HomeTab(),
    FeatureMenuTab(section: FeatureSection.matches),
    FeatureMenuTab(section: FeatureSection.activities),
    FeatureMenuTab(section: FeatureSection.tools),
    ProfileTab(),
  ];

  static const _titles = <String>[
    'Smart Football Fan',
    'Pertandingan',
    'Seru-seruan',
    'Alat Bantu',
    'Profil',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.watch(automaticSyncProvider);

    // Goyang HP 2x -> dialog konfirmasi SOS.
    ref.listen<AsyncValue<DateTime>>(shakeProvider, (prev, next) {
      next.whenOrNull(data: (_) => showSosConfirm(context, ref));
    });
    // Hasil SOS dari mana pun (FAB, goyang, layar SOS) -> snackbar.
    ref.listen<AsyncValue<String?>>(sosProvider, (prev, next) {
      next.whenOrNull(
        data: (m) {
          if (m != null) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(m)));
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
        Expanded(
          child: IndexedStack(index: index, children: _pages),
        ),
      ]),
      floatingActionButton: SosHoldButton(
        size: 64,
        onTriggered: () => ref.read(sosProvider.notifier).trigger(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) =>
            ref.read(tabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer),
            label: 'Laga',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Seru',
          ),
          NavigationDestination(
            icon: Icon(Icons.widgets_outlined),
            selectedIcon: Icon(Icons.widgets),
            label: 'Alat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
