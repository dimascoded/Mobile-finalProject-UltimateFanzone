import '../../football/data/models.dart';
import '../../gamification/data/blockchain.dart';
import 'prediction_repository.dart';

/// Hasil pemeriksaan reveal terhadap blok rantai.
class RevealVerdict {
  const RevealVerdict({
    required this.valid,
    required this.points,
    required this.reason,
    this.commitBlock,
  });

  /// True hanya bila blok commit ada, commit-nya cocok dengan hash yang dihitung
  /// ulang dari `home`/`away` di blok itu, dan blok dibuat sebelum kickoff.
  final bool valid;

  /// Poin yang sah untuk ditulis ke blok result (0 bila tidak valid).
  final int points;

  /// Alasan ditolak, untuk pesan di UI.
  final String reason;

  /// Blok commit yang dipakai sebagai sumber kebenaran.
  final Block? commitBlock;
}

/// Ambil blok `prediction_commit` pertama untuk sebuah laga.
Block? findCommitBlock(List<Block> chain, int matchId) {
  for (final b in chain) {
    if (b.type != Prediction.blockTypeCommit) continue;
    if ((b.data['match'] as num?)?.toInt() == matchId) return b;
  }
  return null;
}

/// Verifikasi reveal terhadap BLOK RANTAI, bukan terhadap nilai yang tersimpan
/// di Hive.
///
/// Ini adalah sumber kebenaran commit-reveal: skor dan salt di Hive bisa diubah
/// seenaknya, tapi `data['commit']` di blok yang sudah di-mine tidak bisa
/// diubah tanpa membuat rantai invalid. Karena itu:
///
/// - `home`/`away` diambil dari blok (bukan dari API saat ini), supaya commit
///   dihitung ulang dengan input yang sama persis seperti saat commit dibuat;
/// - `data['at']` harus lebih awal dari kickoff, jadi predikasi tidak bisa
///   dicatat setelah Knowing hasil akhir.
RevealVerdict verifyReveal({
  required List<Block> chain,
  required Prediction prediction,
  required FootballMatch match,
}) {
  if (isCancelledStatus(match.status)) {
    return const RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Laga dibatalkan atau diundur, tidak ada skor resmi.',
    );
  }
  if (!match.isFinished || !match.hasScore) {
    return const RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Laga belum selesai, hasil belum bisa dibuka.',
    );
  }

  final block = findCommitBlock(chain, prediction.matchId);
  if (block == null) {
    return const RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Tidak ada blok commit untuk laga ini di rantai.',
    );
  }

  final blockCommit = (block.data['commit'] ?? '').toString();
  final blockHome = (block.data['home'] ?? '').toString();
  final blockAway = (block.data['away'] ?? '').toString();
  final blockAt = DateTime.tryParse((block.data['at'] ?? '').toString());

  if (blockCommit.isEmpty) {
    return RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Blok commit tidak memuat commit.',
      commitBlock: block,
    );
  }
  if (blockAt == null) {
    return RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Blok commit tidak memuat waktu pembuatan.',
      commitBlock: block,
    );
  }
  if (!blockAt.isBefore(match.kickoffUtc)) {
    return RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Commit dicatat pada atau setelah kickoff.',
      commitBlock: block,
    );
  }
  final hashMatches = Prediction.verify(
    matchId: prediction.matchId,
    home: blockHome,
    away: blockAway,
    salt: prediction.salt,
    expectedCommit: blockCommit,
  );
  if (!hashMatches) {
    return RevealVerdict(
      valid: false,
      points: 0,
      reason: 'Hash tidak cocok dengan commit di rantai.',
      commitBlock: block,
    );
  }

  return RevealVerdict(
    valid: true,
    points: scorePoints(
      predHome: prediction.homeScore,
      predAway: prediction.awayScore,
      realHome: match.homeScore!,
      realAway: match.awayScore!,
    ),
    reason: 'Commit cocok.',
    commitBlock: block,
  );
}

/// Status laga yang berarti hasil resminya tidak ada.
bool isCancelledStatus(String status) =>
    status == 'POSTPONED' || status == 'CANCELLED' || status == 'SUSPENDED';
