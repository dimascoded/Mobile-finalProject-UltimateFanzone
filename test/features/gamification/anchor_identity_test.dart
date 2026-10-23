import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/utils/app_config.dart';
import 'package:ultimate_fanzone/features/auth/data/identity_store.dart';
import 'package:ultimate_fanzone/features/auth/providers/user_data_cleanup.dart';
import 'package:ultimate_fanzone/features/gamification/data/anchor_store.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_anchor_service.dart';
import 'package:ultimate_fanzone/features/gamification/data/wallet_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:web3dart/web3dart.dart';

class _MemoryIdentityStore implements IdentityStore {
  final values = <String, String>{};

  @override
  String? get(String key) => values[key];

  @override
  Future<void> put(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _BalanceEthClient implements EthClient {
  String? lastAddress;

  BigInt balanceFor(String address) =>
      BigInt.parse(address.substring(2, 6), radix: 16);

  @override
  Future<BigInt> getBalanceWei(String address) async {
    lastAddress = address;
    return balanceFor(address);
  }

  @override
  Future<int> getChainId() => throw UnimplementedError();

  @override
  Future<EthTxStatus> getReceiptStatus(String txHash) =>
      throw UnimplementedError();

  @override
  Future<String?> getTransactionInputUtf8(String txHash) =>
      throw UnimplementedError();

  @override
  Future<String> sendDataTransaction(
    EthPrivateKey credentials,
    String utf8Payload,
    String to,
  ) =>
      throw UnimplementedError();
}

final _invalidateIdentity = Provider<void>((ref) {
  invalidateIdentityProviders(ref);
});

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('ganti akun tidak memperlihatkan anchor atau saldo akun sebelumnya',
      () async {
    var activeUser = 'user-a';
    const storage = FlutterSecureStorage();
    final wallet = WalletRepository(storage, () => activeUser);
    final anchorStore = AnchorStore(_MemoryIdentityStore(), () => activeUser);
    final eth = _BalanceEthClient();

    final container = ProviderContainer(
      overrides: [
        walletRepositoryProvider.overrideWithValue(wallet),
        anchorStoreProvider.overrideWithValue(anchorStore),
        ethClientProvider.overrideWithValue(eth),
      ],
    );
    addTearDown(container.dispose);

    final addressA = await container.read(walletAddressProvider.future);
    final balanceA = await container.read(walletBalanceProvider.future);
    expect(balanceA, eth.balanceFor(addressA));

    await anchorStore.add(AnchorRecord(
      txHash: '0xaaaa',
      headHash: 'hash-a',
      headIndex: 1,
      chainLength: 2,
      createdAtMs: 1,
      explorerUrl: AppConfig.explorerTxUrl('0xaaaa'),
      status: AnchorStatus.confirmed,
    ));
    expect(container.read(anchorsProvider), hasLength(1));

    activeUser = 'user-b';
    container.read(_invalidateIdentity);

    final addressB = await container.read(walletAddressProvider.future);
    final balanceB = await container.read(walletBalanceProvider.future);

    expect(addressB, isNot(addressA));
    expect(balanceB, eth.balanceFor(addressB));
    expect(balanceB, isNot(balanceA));
    expect(container.read(anchorsProvider), isEmpty);
    expect(eth.lastAddress, addressB);
  });

  test('AnchorStore memisahkan data per user dan membatasi 50 record',
      () async {
    var activeUser = 'user-a';
    final backing = _MemoryIdentityStore();
    final store = AnchorStore(backing, () => activeUser);

    for (var i = 0; i < 55; i++) {
      await store.add(AnchorRecord(
        txHash: '0x$i',
        headHash: 'hash-$i',
        headIndex: i,
        chainLength: i + 1,
        createdAtMs: i,
        explorerUrl: AppConfig.explorerTxUrl('0x$i'),
        status: AnchorStatus.pending,
      ));
    }

    final records = store.load();
    expect(records, hasLength(AnchorStore.maxRecords));
    expect(records.first.txHash, '0x54');
    expect(records.last.txHash, '0x5');

    await store.update(AnchorRecord(
      txHash: '0x54',
      headHash: 'hash-54',
      headIndex: 54,
      chainLength: 55,
      createdAtMs: 55,
      explorerUrl: AppConfig.explorerTxUrl('0x54'),
      status: AnchorStatus.confirmed,
    ));
    expect(store.load().first.status, AnchorStatus.confirmed);

    activeUser = 'user-b';
    expect(store.load(), isEmpty);
    expect(
      backing.get(AnchorStore.keyFor('user-a')),
      isNotNull,
    );
  });
}
