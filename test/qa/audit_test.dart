// Audit statis: memastikan tidak ada warna keras (Colors.* atau Color(0x...))
// di luar palet/token di dalam lapisan UI.
//
// Daftar allowlist berisi berkas yang memang butuh warna langsung:
//   * kartu koleksi  -> palet kelangkaan (common/rare/epic/legendary)
//   * penalti        -> papan gawang hitam/putih
//   * game refleks   -> papan gawang hitam/putih
//   * penunjuk stadion -> jarum kompas putih
// Warna `Colors.white`/`white70`/`black` pada ScrimImage tidak masuk pola ini.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _roots = <String>['lib/features', 'lib/core/ui'];

final RegExp _namedColor = RegExp(
  r'Colors\.(green|red|blue|grey|gray|teal|orange|purple|amber|yellow)\b',
);
final RegExp _hexColor = RegExp(r'Color\(0x');

const Set<String> _allowlist = <String>{
  'lib/features/gamification/presentation/card_collection_screen.dart',
  'lib/features/penalty_shootout/presentation/penalty_screen.dart',
  'lib/features/gamification/presentation/game_screen.dart',
  'lib/features/stadium_pointer/presentation/stadium_pointer_screen.dart',
  'lib/features/sos_emergency/presentation/sos_actions.dart',
  'lib/features/sos_emergency/presentation/sos_hold_button.dart',
};

void main() {
  test('tidak ada warna keras di luar palet pada lapisan UI', () {
    final problems = <String>[];

    for (final root in _roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final relative = file.path.replaceAll('\\', '/');
        if (_allowlist.contains(relative)) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (_namedColor.hasMatch(line) || _hexColor.hasMatch(line)) {
            problems.add('$relative:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    for (final problem in problems) {
      debugPrint('[AUDIT] $problem');
    }

    expect(
      problems,
      isEmpty,
      reason: problems.isEmpty
          ? null
          : '\n${problems.length} warna keras di luar palet:\n'
              '${problems.join('\n')}',
    );
  });
}
