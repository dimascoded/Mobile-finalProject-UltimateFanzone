import 'dart:math';

import '../../penalty_shootout/data/penalty_rules.dart';

/// Aturan mini game "Refleks Kiper": murni Dart, tanpa I/O, supaya bisa diuji
/// tanpa widget. Alur data (skor, kombo, level, nyawa) dipegang
/// `reflexProvider`; berkas ini hanya fungsi murni yang mengubah angka.
/// Lihat `docs/feature-map.md` (bagian gamification).

/// Batas waktu awal menepuk zona bola, dalam milidetik (level 1).
const int initialReflexTimeLimitMs = 1200;

/// Pengurangan batas waktu tiap kenaikan level, dalam milidetik.
const int reflexTimeStepMs = 100;

/// Jumlah tangkisan yang dibutuhkan untuk naik satu level.
const int savesPerReflexLevel = 5;

/// Batas waktu minimum supaya permainan tetap bisa dimainkan di level tinggi.
const int minimumReflexTimeLimitMs = 500;

/// Jumlah nyawa awal; habis berarti permainan selesai.
const int reflexLives = 3;

/// Level dari jumlah tangkisan: naik satu level setiap [savesPerReflexLevel].
/// Nilai negatif diperlakukan sebagai 0 sehingga level minimal 1.
int levelForSaves(int saves) =>
    (saves < 0 ? 0 : saves) ~/ savesPerReflexLevel + 1;

/// Batas waktu menepuk untuk [level], menurun [reflexTimeStepMs] per level dan
/// tidak pernah lebih cepat dari [minimumReflexTimeLimitMs].
int timeLimitForLevel(int level) {
  final safeLevel = max(1, level);
  final limit = initialReflexTimeLimitMs - (safeLevel - 1) * reflexTimeStepMs;
  return max(minimumReflexTimeLimitMs, limit);
}

/// Poin satu tangkisan. Bonus bertambah setiap 5 kombo (10, 20, 30, ...).
int scoreForSave(int combo) => 10 * (1 + max(0, combo) ~/ 5);

/// Nyawa setelah meleset; tidak pernah di bawah 0.
int livesAfterMiss(int lives) => max(0, lives - 1);

/// Kombo setelah tangkisan berhasil (selalu +1).
int comboAfterSave(int combo) => max(0, combo) + 1;

/// Kombo direset ke 0 setelah meleset.
int comboAfterMiss(int combo) => 0;

/// Pilih zona bola berikutnya secara acak, menghindari [previous] agar bola
/// tidak muncul di zona yang sama dua kali berturut-turut.
KickZone pickZone(Random rnd, KickZone? previous) {
  final choices =
      KickZone.values.where((zone) => zone != previous).toList(growable: false);
  return choices[rnd.nextInt(choices.length)];
}
