import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/hive_service.dart';

/// Penyedia mode tema aplikasi.
///
/// Menyimpan pilihan tema pengguna (system/light/dark) di Hive pada key
/// `theme_mode` dan tiringkannya lewat [themeModeProvider], sehingga pilihan
/// tema tetap sama saat aplikasi dibuka ulang.
///
/// Nilai diambil dari [HiveService.cache] saat provider pertama kali dibuat.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_load());

  /// Key Hive untuk nama [ThemeMode] yang sedang dipilih.
  static const _key = 'theme_mode';

  /// Membaca mode tema tersimpan; nilai tak dikenal dianggap `system`.
  static ThemeMode _load() {
    switch (HiveService.cache.get(_key)) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  /// Mengganti mode tema dan menyimpannya ke Hive pada key `theme_mode`.
  Future<void> set(ThemeMode m) async {
    state = m;
    await HiveService.cache.put(_key, m.name);
  }
}

/// Provider mode tema aktif; dipakai [MaterialApp] untuk memilih tema
/// terang (`AppTheme.light`) atau gelap (`AppTheme.dark`).
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier());
