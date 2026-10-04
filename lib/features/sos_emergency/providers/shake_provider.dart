import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Emit saat HP digoyang 2x dalam <1 detik (accelerometer > ~25 m/s²).
/// Cooldown 5 detik agar tidak memicu berulang.
final shakeProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  const threshold = 25.0;
  const minGap = Duration(milliseconds: 150);
  const window = Duration(seconds: 1);
  const cooldown = Duration(seconds: 5);

  DateTime? first;
  DateTime? lastTrigger;

  await for (final e in accelerometerEventStream()) {
    final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (g < threshold) continue;

    final now = DateTime.now();
    if (lastTrigger != null && now.difference(lastTrigger) < cooldown) continue;

    if (first == null || now.difference(first) >= window) {
      first = now; // hentakan pertama
    } else if (now.difference(first) >= minGap) {
      first = null;
      lastTrigger = now;
      yield now; // hentakan kedua dalam jendela waktu
    }
  }
});
