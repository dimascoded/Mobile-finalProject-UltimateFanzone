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

  testWidgets('memilih preset 1 jam menambah pengingat', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '1 jam'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '1 jam'), findsOneWidget);
  });

  testWidgets('menambah pengingat keempat menampilkan SnackBar', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '1 jam'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '15 menit'));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNWidgets(3));

    await tester.tap(find.widgetWithText(FilterChip, '3 jam'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Maksimal 3 pengingat.'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(3));
  });

  testWidgets('dialog Tambah sendiri menyimpan 2 hari sebagai 2880 menit',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah sendiri'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('reminder-value')), '2');
    await tester.tap(find.byKey(const Key('reminder-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hari').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '2 hari'), findsOneWidget);
  });

  testWidgets('menghapus chip menghilangkan pengingat', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '30 menit'), findsOneWidget);

    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, '30 menit'),
      matching: find.byType(Icon),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Pengingat dimatikan'), findsOneWidget);
  });

  testWidgets('Kembalikan ke bawaan memulihkan 30 menit', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '1 jam'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '1 jam'), findsOneWidget);

    await tester.tap(find.text('Kembalikan ke bawaan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, '30 menit'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '1 jam'), findsNothing);
  });
}
