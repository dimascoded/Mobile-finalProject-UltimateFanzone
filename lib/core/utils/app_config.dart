/// Semua rahasia diinjeksi saat build, TIDAK di-hardcode:
/// flutter run --dart-define=GEMINI_API_KEY=xxx --dart-define=BACKEND_URL=https://api.example.com
class AppConfig {
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasPartialSupabaseConfig =>
      supabaseUrl.isEmpty != supabaseAnonKey.isEmpty;

  /// Model Gemini. Default `gemini-3.8-flash` (GA, mulai 2026-09-02).
  ///
  /// Catatan: seluruh keluarga gemini-1.x dan gemini-2.5* sudah retired/deprecated
  /// (gemini-2.5* dimatikan pada Oktober 2026), jadi jangan dikembalikan ke
  /// sana. Kalau model ini dimatikan Google, override saat build:
  ///   flutter run --dart-define=GEMINI_MODEL=gemini-3.7-flash
  /// Daftar model aktif: https://ai.google.dev/gemini-api/docs/models
  static const geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');

  /// Kosong = mode mock (login diterima tanpa backend, untuk development).
  static const backendUrl = String.fromEnvironment('BACKEND_URL');

  /// API key gratis dari football-data.org. Kosong = data contoh (bukan jadwal resmi).
  static const footballApiKey = String.fromEnvironment('FOOTBALL_API_KEY');
  static const footballBaseUrl = 'https://api.football-data.org/v4';

  /// Berapa menit sebelum kickoff pengingat dikirim. Nilai produksi 30; saat
  /// uji manual di perangkat bisa diturunkan supaya tidak perlu menunggu
  /// setengah jam:
  ///   flutter run --dart-define=KICKOFF_REMINDER_MINUTES=2
  /// Perhatikan hanya nilai kecil dari 30 yang masuk akal untuk pengingat
  /// "mulai dalam N menit" yang tampil di notifikasi.
  static const kickoffReminderMinutes =
      int.fromEnvironment('KICKOFF_REMINDER_MINUTES', defaultValue: 30);

  static const exchangeRateUrl =
      'https://api.exchangerate-api.com/v4/latest/IDR';
}
