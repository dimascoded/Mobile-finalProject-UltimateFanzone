import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/auth/presentation/login_screen.dart';
import 'package:ultimate_fanzone/features/auth/presentation/register_screen.dart';
import 'package:ultimate_fanzone/features/dashboard/presentation/feedback_screen.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/data/reminder_leads.dart';
import 'package:ultimate_fanzone/features/football/presentation/reminder_settings_screen.dart';
import 'package:ultimate_fanzone/features/football/presentation/team_picker_screen.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/football/providers/kickoff_reminder_provider.dart';
import 'package:ultimate_fanzone/features/sos_emergency/presentation/sos_screen.dart';

/// Repositori klub dalam memori: tidak menyentuh Hive milik perangkat.
class _InMemoryClubRepository extends ClubRepository {
  _InMemoryClubRepository(this._favoriteKey);

  final String? _favoriteKey;

  @override
  String? favoriteKey() => _favoriteKey;

  @override
  Future<void> saveFavorite(String key) async {}
}

/// Sama seperti [KickoffLeadsNotifier] tetapi tidak menyentuh Hive maupun
/// platform notifikasi.
class _InMemoryKickoffLeads extends KickoffLeadsNotifier {
  _InMemoryKickoffLeads() : super();

  @override
  Future<void> set(List<int> leads) async {
    final normalized = normalizeLeads(leads);
    if (!listEquals(state, normalized)) state = normalized;
  }
}

PlClub _club(String key, String name, String tla) => PlClub(
      key: key,
      name: name,
      shortName: name,
      tla: tla,
      city: 'Kota',
      stadium: 'Stadion $name',
      lat: 0,
      lng: 0,
      color: 0xFFEF0107,
      aliases: [name],
    );

final _clubs = <PlClub>[
  _club('arsenal', 'Arsenal', 'ARS'),
  _club('chelsea', 'Chelsea', 'CHE'),
];

List<Override> _overrides({String? favoriteKey}) => [
      clubsProvider.overrideWith((ref) async => _clubs),
      clubCrestProvider.overrideWithValue(const <String, String>{}),
      kickoffLeadsProvider.overrideWith((ref) => _InMemoryKickoffLeads()),
      favoriteClubProvider.overrideWithValue(null),
      clubRepositoryProvider
          .overrideWithValue(_InMemoryClubRepository(favoriteKey)),
    ];

Widget _app(
  WidgetTester tester,
  Widget screen, {
  required ThemeData theme,
  String? favoriteKey,
}) =>
    ProviderScope(
      overrides: _overrides(favoriteKey: favoriteKey),
      child: MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: screen,
        ),
      ),
    );

ThemeData _theme(Brightness b) =>
    b == Brightness.light ? AppTheme.light : AppTheme.dark;

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_phase5a');
    Hive.init(dir.path);
    HiveService.cache = await Hive.openBox<String>('phase5a_box');
  });

  tearDown(() async {
    await HiveService.cache.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final screens = <String, Widget>{
    'LoginScreen': const LoginScreen(),
    'RegisterScreen': const RegisterScreen(),
    'TeamPickerScreen': const TeamPickerScreen(),
    'ReminderSettingsScreen': const ReminderSettingsScreen(),
    'FeedbackScreen': const FeedbackScreen(),
    'SosScreen': const SosScreen(),
  };

  for (final entry in screens.entries) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${entry.key} 320dp + textScaler 1.3 tanpa overflow '
        '(${brightness.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            _app(tester, entry.value, theme: _theme(brightness)),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('LoginScreen menampilkan judul, tagline, dan kartu form',
      (tester) async {
    await tester.pumpWidget(
      _app(tester, const LoginScreen(), theme: AppTheme.light),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ultimate Fanzone'), findsOneWidget);
    expect(find.text('Teman suporter Premier League-mu'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('TeamPickerScreen menandai tim favorit terpilih', (tester) async {
    await tester.pumpWidget(
      _app(
        tester,
        const TeamPickerScreen(),
        theme: AppTheme.light,
        favoriteKey: 'arsenal',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
