import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/prediction_repository.dart';
import 'package:ultimate_fanzone/features/prediction/data/reveal_verifier.dart';
import 'package:ultimate_fanzone/features/prediction/providers/prediction_provider.dart';

class _MemoryChainRepository extends ChainRepository {
  _MemoryChainRepository(this._chain);
  List<Block> _chain;
  @override
  List<Block> load() => List<Block>.of(_chain);
  @override
  Future<void> save(List<Block> chain) async {
    _chain = List<Block>.of(chain);
  }
}

Block _genesis() => Block(
      index: 0,
      timestamp: 0,
      type: 'genesis',
      data: const {},
      owner: 'system',
      prevHash: '0' * 64,
      nonce: 0,
      hash: '0' * 64,
    );

Block _commit({
  required String commit,
  required DateTime at,
  int matchId = 9001,
}) =>
    Block(
      index: 1,
      timestamp: at.millisecondsSinceEpoch ~/ 1000,
      type: Prediction.blockTypeCommit,
      data: {
        'match': matchId,
        'home': 'Arsenal',
        'away': 'Chelsea',
        'commit': commit,
        'at': at.toIso8601String(),
      },
      owner: '0xowner',
      prevHash: '0' * 64,
      nonce: 0,
      hash: '1',
    );

const _salt = 'settle-detail-salt';

Prediction _prediction() => Prediction(
      matchId: 9001,
      homeScore: 2,
      awayScore: 1,
      salt: _salt,
      commit: Prediction.computeCommit(
        matchId: 9001,
        home: 'Arsenal',
        away: 'Chelsea',
        salt: 'wrong-salt',
      ),
    );

FootballMatch _finishedMatch({bool withScore = true}) => FootballMatch(
      id: 9001,
      kickoffUtc: DateTime.utc(2026, 2, 1),
      status: 'FINISHED',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
      homeScore: withScore ? 2 : null,
      awayScore: withScore ? 1 : null,
    );

Future<({SettledPrediction? settled, String? reason, String? debug})> _result(
  List<Block> chain,
  FootballMatch match,
) async {
  final container = ProviderContainer(overrides: [
    chainRepositoryProvider
        .overrideWithValue(_MemoryChainRepository(chain)),
  ]);
  addTearDown(container.dispose);
  return container.read(settleActionProvider).settleDetailed(match, _prediction());
}

Future<String?> _reason(List<Block> chain, FootballMatch match) async =>
    (await _result(chain, match)).reason;

void main() {
  final kickoff = DateTime.utc(2026, 2, 1);

  test('settleDetailed: tanpa blok commit', () async {
    final reason = await _reason([_genesis()], _finishedMatch());
    expect(reason, kNoCommitReason);
  });

  test('settleDetailed: hash tidak cocok + debug', () async {
    final r = await _result(
      [
        _genesis(),
        _commit(
            commit:
                'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
            at: kickoff.subtract(const Duration(hours: 1))),
      ],
      _finishedMatch(),
    );
    expect(r.reason, kHashMismatchReason);
    expect(r.settled, isNull);
    final debug = r.debug;
    expect(debug, isNotNull);
    expect(debug, contains('match=9001'));
    expect(debug, contains('blok_commit=1'));
    expect(debug, contains('pred=${_prediction().commit.substring(0, 8)}'));
    expect(debug, contains('blok=abcdef01'));
    expect(debug, contains('commit_sama=false'));
  });

  test('settleDetailed: dua blok commit dipakai yang pertama', () async {
    // Blok pertama salah, blok kedua benar untuk salt prediksi. verifyReveal
    // harus tetap memakai blok PERTAMA, jadi hasilnya invalid + debug
    // menghitung dua blok.
    final r = await _result(
      [
        _genesis(),
        _commit(
            commit: '0000000000000000000000000000000000000000',
            at: kickoff.subtract(const Duration(hours: 2))),
        _commit(
            commit: Prediction.computeCommit(
              matchId: 9001,
              home: 'Arsenal',
              away: 'Chelsea',
              salt: _salt,
            ),
            at: kickoff.subtract(const Duration(hours: 1))),
      ],
      _finishedMatch(),
    );
    expect(r.reason, kHashMismatchReason);
    expect(r.debug, contains('blok_commit=2'));
  });

  test('settleDetailed: commit dicatat setelah kickoff', () async {
    final reason = await _reason(
      [
        _genesis(),
        _commit(commit: 'apa-saja', at: kickoff.add(const Duration(minutes: 1))),
      ],
      _finishedMatch(),
    );
    expect(reason, 'Commit dicatat pada atau setelah kickoff.');
  });

  test('settleDetailed: laga tanpa skor resmi', () async {
    final reason = await _reason(
      [_genesis()],
      _finishedMatch(withScore: false),
    );
    expect(reason, 'Skor resmi belum tersedia');
  });
}
