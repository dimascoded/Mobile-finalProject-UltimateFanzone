import '../../../core/utils/crypto_utils.dart';

/// Prediksi skor commit-reveal. Tanpa odds/taruhan: hanya poin.
///
/// Alur sesuai rubrik:
/// 1. Sebelum kickoff, pengguna memilih skor (mis. 2-1). Aplikasi membuat
///    `salt` acak dan menyimpan
///       commit = sha256('$matchId|$home|$away|$salt')
///    di blok `prediction_commit`. Salt TIDAK ikut ditulis di blok itu,
///    jadi skor + salt masih tersembunyi.
/// 2. Blok di-mine (proof-of-work), jadi commit mustahil diubah tanpa
///    membuat rantai invalid.
/// 3. Sesudah laga FINISHED, blok `prediction_result` membocorkan salt dan
///    skor tebakan. Validasi: sha256 dengan salt terUNGKAP harus menghasilkan
///    commit yang sama seperti di blok commit. Kalau berbeda, prediksi tidak
///    sah dan poin tidak diberikan.
///
/// Fungsi-fungsi ini murni (tanpa I/O) supaya bisa diuji tanpa emulator.
class Prediction {
  Prediction({
    required this.matchId,
    required this.homeScore,
    required this.awayScore,
    required this.salt,
    required this.commit,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? _epoch;

  final int matchId;
  final int homeScore;
  final int awayScore;
  final String salt;
  final String commit;

  /// Kapan prediksi dicatat. Dikirim ke server sebagai penanda urutan, bukan
  /// sebagai rahasia (lihat `predictionCommitToJson`).
  final DateTime createdAt;

  static final DateTime _epoch =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static const blockTypeCommit = 'prediction_commit';
  static const blockTypeResult = 'prediction_result';

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'salt': salt,
        'commit': commit,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  /// Parse satu prediksi. Melempar [FormatException] bila data tidak lengkap,
  /// supaya pemanggil bisa melewati item ini saja (bukan seluruh daftar).
  factory Prediction.fromJson(Map<String, dynamic> j) {
    final matchId = (j['matchId'] as num?)?.toInt();
    if (matchId == null) {
      throw const FormatException('matchId tidak ada');
    }
    final salt = j['salt'];
    final commit = j['commit'];
    if (salt is! String ||
        commit is! String ||
        salt.isEmpty ||
        commit.isEmpty) {
      throw const FormatException('salt atau commit tidak ada');
    }
    return Prediction(
      matchId: matchId,
      homeScore: (j['homeScore'] as num?)?.toInt() ?? 0,
      awayScore: (j['awayScore'] as num?)?.toInt() ?? 0,
      salt: salt,
      commit: commit,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
    );
  }

  static String computeCommit({
    required int matchId,
    required String home,
    required String away,
    required String salt,
  }) =>
      CryptoUtils.sha256Hash('$matchId|$home|$away|$salt');

  /// Data blok commit. SENGAJA tidak memuat salt maupun skor.
  static Map<String, dynamic> commitData({
    required int matchId,
    required String home,
    required String away,
    required String commit,
    required DateTime at,
  }) =>
      {
        'match': matchId,
        'home': home,
        'away': away,
        'commit': commit,
        'at': at.toIso8601String(),
      };

  /// Data blok hasil: salt dibuka, skor tebakan dibuka, skor resmi, dan poin.
  static Map<String, dynamic> resultData({
    required int matchId,
    required String salt,
    required int predHome,
    required int predAway,
    required int realHome,
    required int realAway,
    required int points,
  }) =>
      {
        'match': matchId,
        'salt': salt,
        'pred': '$predHome-$predAway',
        'final': '$realHome-$realAway',
        'points': points,
      };

  /// Reveal sah bila hash dengan salt terbuka == commit yang tercatat.
  static bool verify({
    required int matchId,
    required String home,
    required String away,
    required String salt,
    required String expectedCommit,
  }) =>
      computeCommit(
        matchId: matchId,
        home: home,
        away: away,
        salt: salt,
      ) ==
      expectedCommit;
}

/// Poin dari tebakan skor. Tidak ada uang sungguhan, hanya poin:
///
/// - tebak pas              -> 3 poin
/// - meleset 1 gol          -> 2 poin
/// - meleset 2 gol          -> 1 poin
/// - meleset >2 gol         -> 0 poin
/// - bonus +1 poin bila arah hasil (menang/seri/kalah) tebak benar
///
/// [scorePoints] selalu nonnegative.
int scorePoints({
  required int predHome,
  required int predAway,
  required int realHome,
  required int realAway,
}) {
  final diff = (predHome - realHome).abs() + (predAway - realAway).abs();
  final int points;
  if (diff == 0) {
    points = 3;
  } else if (diff == 1) {
    points = 2;
  } else if (diff == 2) {
    points = 1;
  } else {
    points = 0;
  }
  final predSign = (predHome > predAway) ? 1 : (predHome < predAway ? -1 : 0);
  final realSign = (realHome > realAway) ? 1 : (realHome < realAway ? -1 : 0);
  return points + (predSign == realSign ? 1 : 0);
}
