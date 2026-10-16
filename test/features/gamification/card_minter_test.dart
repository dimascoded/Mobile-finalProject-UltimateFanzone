import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';

/// Repositori rantai dalam memory: tidak menyentuh Hive maupun SQLite.
class FakeChainRepository extends ChainRepository {
  FakeChainRepository([List<Block>? initial])
      : _chain = initial ?? [Blockchain.genesis()];

  List<Block> _chain;

  @override
  List<Block> load() => List<Block>.of(_chain);

  @override
  Future<void> save(List<Block> chain) async {
    _chain = List<Block>.of(chain);
  }
}

PlClub club(String key, String stadium) => PlClub(
      key: key,
      name: '$key FC',
      shortName: key,
      tla: key.substring(0, 3).toUpperCase(),
      city: 'Kota',
      stadium: stadium,
      lat: 0,
      lng: 0,
      color: 0xFF000000,
      aliases: [key],
    );

ProviderContainer makeContainer(FakeChainRepository repo) => ProviderContainer(
      overrides: [
        chainRepositoryProvider.overrideWithValue(repo),
        walletAddressProvider.overrideWith((ref) async => '0xowner'),
        clubsProvider.overrideWith((ref) async => [
              club('arsenal', 'Emirates'),
              club('chelsea', 'Bridge'),
            ]),
      ],
    );

void main() {
  test('mint pertama mengembalikan kartu dan menambah satu blok', () async {
    final container = makeContainer(FakeChainRepository());
    addTearDown(container.dispose);

    final card = await container
        .read(cardMinterProvider)
        .mintCard(source: 'penalty', ref: 'penalty:2026-01-01');

    final chain = container.read(chainProvider);
    expect(card, isNotNull);
    expect(chain.length, 2);
    expect(chain.last.type, 'card');
    expect(chain.last.data['source'], 'penalty');
    expect(chain.last.data['ref'], 'penalty:2026-01-01');
  });

  test('mint kedua dengan ref sama mengembalikan null, rantai tidak berubah',
      () async {
    final container = makeContainer(FakeChainRepository());
    addTearDown(container.dispose);
    final minter = container.read(cardMinterProvider);

    final first =
        await minter.mintCard(source: 'penalty', ref: 'penalty:2026-01-01');
    final lengthAfterFirst = container.read(chainProvider).length;
    final second =
        await minter.mintCard(source: 'penalty', ref: 'penalty:2026-01-01');

    expect(first, isNotNull);
    expect(second, isNull);
    expect(container.read(chainProvider).length, lengthAfterFirst);
  });

  test('ref berbeda mencetak kartu terpisah', () async {
    final container = makeContainer(FakeChainRepository());
    addTearDown(container.dispose);
    final minter = container.read(cardMinterProvider);

    final a =
        await minter.mintCard(source: 'penalty', ref: 'penalty:2026-01-01');
    final b =
        await minter.mintCard(source: 'penalty', ref: 'penalty:2026-01-02');

    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(container.read(chainProvider).length, 3);
  });

  test('rantai tetap valid setelah mint', () async {
    final container = makeContainer(FakeChainRepository());
    addTearDown(container.dispose);

    await container
        .read(cardMinterProvider)
        .mintCard(source: 'reflex', ref: 'reflex:2026-01-01');

    expect(Blockchain.isValid(container.read(chainProvider)), isTrue);
  });

  test('lastEarnedCardProvider diisi setelah sukses', () async {
    final container = makeContainer(FakeChainRepository());
    addTearDown(container.dispose);

    expect(container.read(lastEarnedCardProvider), isNull);
    final card = await container
        .read(cardMinterProvider)
        .mintCard(source: 'stamp', ref: 'stamp:arsenal');

    expect(card, isNotNull);
    expect(container.read(lastEarnedCardProvider), same(card));
  });
}
