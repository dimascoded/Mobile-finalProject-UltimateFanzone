/// Semua rahasia diinjeksi saat build, TIDAK di-hardcode:
/// flutter run --dart-define=GEMINI_API_KEY=xxx --dart-define=BACKEND_URL=https://api.example.com
class AppConfig {
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-1.5-flash');

  /// Kosong = mode mock (login diterima tanpa backend, untuk development).
  static const backendUrl = String.fromEnvironment('BACKEND_URL');

  /// API key gratis dari football-data.org. Kosong = data contoh (bukan jadwal resmi).
  static const footballApiKey = String.fromEnvironment('FOOTBALL_API_KEY');
  static const footballBaseUrl = 'https://api.football-data.org/v4';

  static const exchangeRateUrl =
      'https://api.exchangerate-api.com/v4/latest/IDR';
}
