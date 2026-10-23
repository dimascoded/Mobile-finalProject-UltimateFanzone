/// Semua rahasia diinjeksi saat build, TIDAK di-hardcode. Isi `env.json`
/// (contoh di `env.example.json`) lalu jalankan:
///   flutter run --dart-define-from-file=env.json
class AppConfig {
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Kunci privat dompet jangkar bersama untuk semua transaksi anchor Sepolia.
  ///
  /// Kosong = pakai dompet per pengguna seperti sebelumnya. Nilai ini hanya
  /// diinjeksi saat build dan tidak pernah ditulis ke penyimpanan.
  static const anchorPrivateKey = String.fromEnvironment('ANCHOR_PRIVATE_KEY');

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

  /// Kandidat cadangan bila [geminiModel] tidak tersedia (HTTP 404). Dicoba
  /// berurutan setelah model yang dikonfigurasi dan model yang terakhir berhasil.
  static const geminiFallbackModels = [
    'gemini-3.8-flash',
    'gemini-3.5-flash-lite',
    'gemini-flash-latest',
  ];

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

  /// Endpoint JSON-RPC Sepolia. Kosong = fitur chain anchor melaporkan
  /// "RPC belum dikonfigurasi" tanpa membuat aplikasi crash.
  static const sepoliaRpcUrl = String.fromEnvironment('SEPOLIA_RPC_URL');

  /// Chain id Ethereum Sepolia (testnet). Anchor hanya ditandatangani untuk
  /// jaringan ini, tidak pernah untuk mainnet atau jaringan lain.
  static const sepoliaChainId = 11155111;

  /// Basis tautan explorer Sepolia untuk transaksi anchor.
  static const explorerBase = 'https://sepolia.etherscan.io';

  /// Tautan explorer untuk transaksi [txHash].
  static String explorerTxUrl(String txHash) => '$explorerBase/tx/$txHash';

  /// Tautan explorer untuk alamat dompet [address].
  static String explorerAddressUrl(String address) =>
      '$explorerBase/address/$address';

  /// Faucet ETH Sepolia. URL belum diverifikasi ulang pada implementasi ini.
  static const faucetUrl = 'https://sepolia-faucet.pk910.de/';
}
