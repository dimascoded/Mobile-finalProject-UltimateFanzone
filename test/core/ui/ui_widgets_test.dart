import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/core/theme/app_tokens.dart';
import 'package:ultimate_fanzone/core/ui/settings_section.dart';
import 'package:ultimate_fanzone/core/ui/stat_tile.dart';

/// Membangun widget di bawah MaterialApp dengan skala teks yang bisa diatur.
Widget _host(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
  double scale = 1.0,
}) =>
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    );

/// Tiga StatTile sejajar, meniru baris statistik di tab Profil.
Widget _statsRow() => const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: StatTile(
              icon: Icon(Icons.approval_outlined),
              value: '12',
              label: 'Stempel',
              detail: 'PassportScreen',
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: StatTile(
              icon: Icon(Icons.style_outlined),
              value: '3',
              label: 'Kartu',
              detail: 'Card Collection',
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: StatTile(
              icon: Icon(Icons.emoji_events_outlined),
              value: '7',
              label: 'Pencapaian',
              detail: 'total',
            ),
          ),
        ],
      ),
    );

void main() {
  group('StatTile', () {
    testWidgets('menampilkan nilai, label, detail, dan label semantik',
        (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _host(
          tester,
          StatTile(
            icon: const Icon(Icons.approval_outlined),
            value: '12',
            label: 'Stempel',
            detail: 'PassportScreen',
            onTap: () => taps++,
          ),
          theme: AppTheme.light,
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('Stempel'), findsOneWidget);
      expect(find.text('PassportScreen'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Stempel: 12, PassportScreen'),
        findsOneWidget,
      );

      await tester.tap(find.text('Stempel'));
      expect(taps, 1);
      handle.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        'tiga kolom 320dp + textScaler 1.3 tanpa overflow (${brightness.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              tester,
              _statsRow(),
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              scale: 1.3,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Pencapaian'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('SettingsSection', () {
    testWidgets('menampilkan judul, tile, pemisah, dan memanggil onTap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          tester,
          SettingsSection(
            title: 'Data',
            children: [
              SettingsTile(
                icon: const Icon(Icons.sync),
                title: 'Cadangan ke Cloud',
                subtitle: 'Otomatis saat ada internet.',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => taps++,
              ),
              SettingsTile(
                icon: const Icon(Icons.logout),
                title: 'Keluar',
                subtitle: 'Hapus sesi dari perangkat ini',
                destructive: true,
                onTap: () => taps++,
              ),
            ],
          ),
          theme: AppTheme.light,
        ),
      );

      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Cadangan ke Cloud'), findsOneWidget);
      expect(find.text('Keluar'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);

      await tester.tap(find.text('Keluar'));
      expect(taps, 1);
    });

    for (final brightness in Brightness.values) {
      testWidgets(
        'subjudul panjang 320dp + textScaler 1.3 tanpa overflow '
        '(${brightness.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _host(
              tester,
              SettingsSection(
                title: 'Keamanan',
                children: [
                  SettingsTile(
                    icon: const Icon(Icons.fingerprint),
                    title: 'Biometrik',
                    subtitle: 'Gunakan sidik jari saat membuka aplikasi '
                        'setiap kali kembali ke depan.',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                  SettingsTile(
                    icon: const Icon(Icons.sync),
                    title: 'Cadangan ke Cloud',
                    subtitle: 'Otomatis saat ada internet, termasuk '
                        'pengeluaran dan prediksi.',
                    onTap: () {},
                  ),
                ],
              ),
              theme: brightness == Brightness.light
                  ? AppTheme.light
                  : AppTheme.dark,
              scale: 1.3,
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
