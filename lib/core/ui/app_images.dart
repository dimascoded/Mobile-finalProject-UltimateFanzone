/// Path aset gambar bersama, dipakai lewat `ScrimImage`, `HomeHero`, dan
/// header tiap fitur. Semua file berada di `assets/images/` (terdaftar di
/// `pubspec.yaml`).
abstract final class AppImages {
  /// Latar gawang untuk mini game Refleks Kiper.
  static const String gameGoal = 'assets/images/game_goal.webp';

  /// Hero "malam laga" di beranda.
  static const String heroMalamLaga = 'assets/images/hero_malam_laga.webp';

  /// Header layar bertema pertandingan (mis. Paspor, Away Day).
  static const String headerLaga = 'assets/images/header_laga.webp';

  /// Header layar bertema "seru-seruan" (mis. Penalty, Refleks).
  static const String headerSeru = 'assets/images/header_seru.webp';

  /// Header layar bertema alat bantu (mis. Pundit, Lens).
  static const String headerAlat = 'assets/images/header_alat.webp';

  /// Latar layar login.
  static const String bgLogin = 'assets/images/bg_login.webp';
}
