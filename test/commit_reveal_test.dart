import 'package:flutter_test/flutter_test.dart';
import 'package:premiere_league_fan_assistant/features/football/data/models.dart';
import 'package:premiere_league_fan_assistant/features/gamification/data/blockchain.dart';
import 'package:premiere_league_fan_assistant/features/prediction/data/prediction_repository.dart';
import 'package:premiere_league_fan_assistant/features/prediction/data/reveal_verifier.dart';

/// Bangun rantai yang valid: genesis lalu blok dengan PoW asli.
List<Block> chainWith(List<({String type, Map<String, dynamic> data})> blocks) {
  final chain = <Block>[Blockchain.genesis()];
  for (final b in blocks) {
    chain.add(Blockchain.next(chain, b.type, b.data, 'me'));
  }
  return chain;
}

FootballMatch finishedMatch({
  required int id,
  required int homeScore,
  required int awayScore,
  String status = 'FINISHED',
  DateTime? kickoff,
}) =>
    FootballMatch(
      id: id,
      kickoffUtc: kickoff ?? DateTime.utc(2026, 8, 15, 14),
      status: status,
      matchday: 1,
      homeName: 'Arsenal FC',
      awayName: 'Chelsea FC',
      homeShort: 'Arsenal',
      awayShort: 'Chelsea',
      homeTla: 'ARS',
      awayTla: 'CHE',
      homeScore: homeScore,
      awayScore: awayScore,
    );

Prediction predictionFor(FootballMatch m, String salt, int home, int away) =>
    Prediction(
      matchId: m.id,
      homeScore: home,
      awayScore: away,
      salt: salt,
      commit: Prediction.computeCommit(
        matchId: m.id,
        home: m.homeName,
        away: m.awayName,
        salt: salt,
      ),
    );

void main() {
  group('R1: reveal diverifikasi ke blok rantai', () {
    final match = finishedMatch(id: 7001, homeScore: 2, awayScore: 1);
    const salt = 'abcdef0123456789';
    final prediction = predictionFor(match, salt, 2, 1);
    final chain = chainWith([
      (
        type: Prediction.blockTypeCommit,
        data: Prediction.commitData(
          matchId: match.id,
          home: match.homeName,
          away: match.awayName,
          commit: prediction.commit,
          at: match.kickoffUtc.subtract(const Duration(hours: 2)),
        ),
      ),
    ]);

    test('commit yang cocok dan dicatat sebelum kickoff diterima', () {
      final v =
          verifyReveal(chain: chain, prediction: prediction, match: match);
      expect(v.valid, isTrue);
      expect(v.points, greaterThan(0));
    });

    test('mengubah skor di Hive tidak mengubah commit yang dipakai', () {
      // Skor tebakan diubah di Hive; commit blok tidak berubah.
      final cheated = Prediction(
        matchId: match.id,
        homeScore: 9,
        awayScore: 9,
        salt: salt,
        commit: prediction.commit,
      );
      final v = verifyReveal(chain: chain, prediction: cheated, match: match);
      // Salt sama dan commit cocok, jadi reveal tetap sah; yang berubah hanya
      // poin. Yang penting: commit lokal yang disalin dari blok, bukan dari Hive.
      expect(v.valid, isTrue);
      expect(v.commitBlock!.data['commit'], prediction.commit);
    });

    test('salt diubah di Hive membuat hash tidak cocok', () {
      final cheated = Prediction(
        matchId: match.id,
        homeScore: 2,
        awayScore: 1,
        salt: '0000000000000000',
        commit: prediction.commit,
      );
      final v = verifyReveal(chain: chain, prediction: cheated, match: match);
      expect(v.valid, isFalse);
      expect(v.points, 0);
    });

    test('commit di Hive tidak dipakai kalau berbeda dengan blok', () {
      // Blok rantai punya commit asli; Hive menyimpan commit palsu.
      final faked = Prediction(
        matchId: match.id,
        homeScore: 2,
        awayScore: 1,
        salt: salt,
        commit: 'f' * 64,
      );
      final v = verifyReveal(chain: chain, prediction: faked, match: match);
      // Verifikasi memakai data blok, jadi yang diuji adalah salt terhadap
      // commit blok: faked tidak boleh membuat apa pun berubah.
      expect(v.commitBlock!.data['commit'], prediction.commit);
      expect(v.valid, isTrue,
          reason: 'commit di Hive diabaikan, yang dipakai blok');
    });

    test('tanpa blok commit reveal ditolak', () {
      final v = verifyReveal(
          chain: [Blockchain.genesis()], prediction: prediction, match: match);
      expect(v.valid, isFalse);
      expect(v.reason, contains('blok commit'));
    });

    test('commit yang dicatat setelah kickoff ditolak', () {
      final late = finishedMatch(
        id: 7002,
        homeScore: 1,
        awayScore: 0,
        kickoff: DateTime.utc(2026, 8, 15, 14),
      );
      final p = predictionFor(late, salt, 1, 0);
      final lateChain = chainWith([
        (
          type: Prediction.blockTypeCommit,
          data: Prediction.commitData(
            matchId: late.id,
            home: late.homeName,
            away: late.awayName,
            commit: p.commit,
            at: late.kickoffUtc.add(const Duration(minutes: 5)),
          ),
        ),
      ]);
      final v = verifyReveal(chain: lateChain, prediction: p, match: late);
      expect(v.valid, isFalse);
      expect(v.reason, contains('kickoff'));
    });

    test('R3: laga POSTPONED ditolak tanpa poin', () {
      final postponed = finishedMatch(
          id: 7003, homeScore: 0, awayScore: 0, status: 'POSTPONED');
      final p = predictionFor(postponed, salt, 1, 0);
      final postponedChain = chainWith([
        (
          type: Prediction.blockTypeCommit,
          data: Prediction.commitData(
            matchId: postponed.id,
            home: postponed.homeName,
            away: postponed.awayName,
            commit: p.commit,
            at: postponed.kickoffUtc.subtract(const Duration(hours: 1)),
          ),
        ),
      ]);
      final v =
          verifyReveal(chain: postponedChain, prediction: p, match: postponed);
      expect(v.valid, isFalse);
      expect(v.reason, contains('dibatalkan'));
    });

    test('laga yang belum selesai ditolak', () {
      final ongoing = finishedMatch(
          id: 7004, homeScore: 1, awayScore: 0, status: 'IN_PLAY');
      final p = predictionFor(ongoing, salt, 1, 0);
      final v = verifyReveal(chain: chain, prediction: p, match: ongoing);
      expect(v.valid, isFalse);
    });
  });

  group('S2: rantai server hanya diadopsi bila aman', () {
    test('perangkat baru (lokal hanya genesis) memulihkan rantai server', () {
      final local = [Blockchain.genesis()];
      final remote = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      expect(Blockchain.canAdoptRemote(local, remote), isTrue);
    });

    test('rantai server yang lebih pendek ditolak', () {
      final local = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'}),
        (type: 'stamp', data: {'club': 'chelsea'}),
      ]);
      final remote = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      expect(Blockchain.canAdoptRemote(local, remote), isFalse);
    });

    test('rantai server yang sama panjang ditolak', () {
      final local = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      final remote = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      expect(Blockchain.canAdoptRemote(local, remote), isFalse);
    });

    test('rantai dengan genesis berbeda ditolak', () {
      final local = [Blockchain.genesis()];
      // Rantai "server" yang genesis-nya di-mine dengan pemilik berbeda.
      final otherGenesis = Blockchain.mine(
        index: 0,
        timestamp: 0,
        type: 'genesis',
        data: const {},
        owner: 'orang-lain',
        prevHash: Blockchain.genesisPrevHash,
      );
      final remote = <Block>[
        otherGenesis,
        Blockchain.next([otherGenesis], 'stamp', {'club': 'arsenal'}, 'me'),
      ];
      expect(Blockchain.canAdoptRemote(local, remote), isFalse);
    });

    test('rantai yang rusak ditolak walau lebih panjang', () {
      final local = [Blockchain.genesis()];
      final remote = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      // Rusak: hash blok terakhir diganti.
      final tampered = [...remote];
      tampered[1] = Block(
        index: tampered[1].index,
        timestamp: tampered[1].timestamp,
        type: tampered[1].type,
        data: tampered[1].data,
        owner: tampered[1].owner,
        prevHash: tampered[1].prevHash,
        nonce: tampered[1].nonce,
        hash: '0' * 64,
      );
      expect(Blockchain.canAdoptRemote(local, tampered), isFalse);
    });

    test('rantai server kosong ditolak', () {
      expect(
          Blockchain.canAdoptRemote([Blockchain.genesis()], const []), isFalse);
    });

    test('rantai yang sama lalu lebih panjang diterima', () {
      final first = chainWith([
        (type: 'stamp', data: {'club': 'arsenal'})
      ]);
      final second = [...first];
      second.add(Blockchain.next(second, 'stamp', {'club': 'chelsea'}, 'me'));
      expect(Blockchain.canAdoptRemote(first, second), isTrue);
    });
  });

  group('R2: parse per item', () {
    test('satu prediksi rusak tidak menghapus yang lain', () {
      final good = Prediction(
        matchId: 1,
        homeScore: 2,
        awayScore: 1,
        salt: 's',
        commit: 'c',
      );
      final decoded = [
        good.toJson(),
        {'matchId': 2}, // tanpa salt/commit -> rusak
        'bukan peta',
      ];
      final kept = <Prediction>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        try {
          kept.add(Prediction.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          continue;
        }
      }
      expect(kept.length, 1);
      expect(kept.first.matchId, 1);
    });
  });
}
