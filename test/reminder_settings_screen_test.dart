import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/features/football/data/reminder_leads.dart';
import 'package:ultimate_fanzone/features/football/presentation/reminder_settings_screen.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/football/providers/kickoff_reminder_provider.dart';

/// Notifier dalam memori: sama dengan [KickoffLeadsNotifier] tetapi tidak
/// menyentuh Hive maupun platform notifikasi, sehingga uji widget tidak
/// menyisakan penulisan yang belum selesai.
class _InMemoryKickoffLeads extends KickoffLeadsNotifier {
  _InMemoryKickoffLeads() : super();

  @override
  Future<void> set(List<int> leads) async {
    final normalized = normalizeLeads(leads);
    if (!listEquals(state, normalized)) state = normalized;
  }
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sgt_reminder_settings');
    Hive.init(dir.path);
    HiveService.cache =
        await Hive.openBox<String>('app_cache_reminder_settings');
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget wrap() => ProviderScope(
        overrides: [
          kickoffLeadsProvider.overrideWith((ref) => _InMemoryKickoffLeads()),
          favoriteClubProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: ReminderSettingsScreen()),
      );

  testWidgets('typing 0/1/30 shows preview and adds 90 minutes', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('reminder-hours')), '1');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('reminder-minutes')), '30');
    await tester.pump();

    expect(find.text('= 1 jam 30 menit'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('reminder-add')))
        .enabled, isTrue);

    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();

    expect(find.widgetWithText(InputChip, '1 jam 30 menit'), findsOneWidget);
    expect(find.text('1 jam 30 menit'), findsAtLeastNWidgets(1));
    expect((tester.widget(find.byKey(const Key('reminder-hours')))
            as TextField)
        .controller!
        .text, isEmpty);
    expect((tester.widget(find.byKey(const Key('reminder-minutes')))
            as TextField)
        .controller!
        .text, isEmpty);
    expect((tester.widget(find.byKey(const Key('reminder-days')))
            as TextField)
        .controller!
        .text, isEmpty);
  });

  testWidgets('all fields empty or zero -> Tambah disabled', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byKey(const Key('reminder-add')))
        .enabled, isFalse);

    await tester.enterText(find.byKey(const Key('reminder-days')), '0');
    await tester.enterText(find.byKey(const Key('reminder-hours')), '0');
    await tester.enterText(find.byKey(const Key('reminder-minutes')), '0');
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byKey(const Key('reminder-add')))
        .enabled, isFalse);
  });

  testWidgets('8 days -> Maksimal 7 hari and nothing added', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('reminder-days')), '8');
    await tester.pump();

    expect(find.text('Maksimal 7 hari.'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '8 hari'), findsNothing);

    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();
    expect(find.byType(InputChip), findsOneWidget); // only default 30 menit
  });

  testWidgets('adding a 4th reminder -> SnackBar Maksimal 3 pengingat',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('reminder-hours')), '1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('reminder-minutes')), '15');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();

    expect(find.byType(InputChip), findsNWidgets(3));

    await tester.enterText(find.byKey(const Key('reminder-hours')), '3');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Maksimal 3 pengingat.'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(3));
  });

  testWidgets('adding an existing value adds nothing', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.widgetWithText(InputChip, '30 menit'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('reminder-minutes')), '30');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();

    expect(find.byType(InputChip), findsNWidgets(1));
  });

  testWidgets('deleting a chip works', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.widgetWithText(InputChip, '30 menit'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, '30 menit'),
      matching: find.byType(Icon),
    ));
    await tester.pump();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Pengingat dimatikan'), findsOneWidget);
  });

  testWidgets('Kembalikan ke bawaan works', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('reminder-hours')), '1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('reminder-add')));
    await tester.pump();
    expect(find.widgetWithText(InputChip, '1 jam'), findsOneWidget);

    await tester.tap(find.text('Kembalikan ke bawaan'));
    await tester.pump();

    expect(find.widgetWithText(InputChip, '30 menit'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '1 jam'), findsNothing);
  });

  testWidgets('no preset chips and no dialog', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Pilihan cepat'), findsNothing);
    expect(find.widgetWithText(FilterChip, '1 jam'), findsNothing);
    expect(find.text('Tambah sendiri'), findsNothing);
    expect(find.byKey(const Key('reminder-value')), findsNothing);
    expect(find.byKey(const Key('reminder-unit')), findsNothing);
  });

  testWidgets('no overflow at 360 dp and text scale 1.3', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(tester.takeException(), isNull);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  });
}
