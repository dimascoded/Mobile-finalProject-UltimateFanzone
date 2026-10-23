import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/utils/app_config.dart';
import 'package:ultimate_fanzone/features/auth/data/identity_store.dart';
import 'package:ultimate_fanzone/features/gamification/data/anchor_store.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_anchor_service.dart'
    as anchor;
import 'package:ultimate_fanzone/features/gamification/data/wallet_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/anchor_coordinator.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:web3dart/web3dart.dart';

class _MemoryStore extends AnchorStore {
  _MemoryStore(this._records, String userId)
      : super(_DummyIdentityStore(), () => userId);

  final List<anchor.AnchorRecord> _records;

  @override
  List<anchor.AnchorRecord> load() => List<anchor.AnchorRecord>.from(_records);

  @override
  Future<void> add(anchor.AnchorRecord record) async {
    _records.removeWhere((r) => r.txHash == record.txHash);
    _records.insert(0, record);
  }

  @override
  Future<void> update(anchor.AnchorRecord record) async {
    final index = _records.indexWhere((r) => r.txHash == record.txHash);
    if (index < 0) {
      _records.insert(0, record);
      return;
    }
    _records[index] = record;
  }
}

class _DummyIdentityStore implements IdentityStore {
  @override
  String? get(String key) => null;
  @override
  Future<void> put(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

anchor.AnchorRecord _record(
  Block block, {
  String txHash = '0xabc',
  anchor.AnchorStatus status = anchor.AnchorStatus.pending,
}) =>
    anchor.AnchorRecord(
      txHash: txHash,
      headHash: block.hash,
      headIndex: block.index,
      chainLength: 1,
      createdAtMs: 1,
      explorerUrl: AppConfig.explorerTxUrl(txHash),
      status: status,
    );

void main() {
  test('RPC kosong tidak menyentuh storage dan berhenti', () async {
    final records = <anchor.AnchorRecord>[];
    final store = _MemoryStore(records, 'u1');
    var chainRead = 0;
    var serviceCalls = 0;

    final coordinator = AnchorCoordinator(
      null,
      rpcConfigured: false,
      readChain: () {
        chainRead++;
        return [Blockchain.genesis()];
      },
      service: () {
        serviceCalls++;
        throw StateError('should not call');
      },
      store: () => store,
      currentUserId: () => 'u1',
      listenConnectivity: false,
    );

    await coordinator.ensureAnchored();
    expect(coordinator.state, AnchorStatus.notConfigured);
    expect(chainRead, 0);
    expect(serviceCalls, 0);
    expect(records, isEmpty);
  });

  test('tanpa unanchored stamps tidak mengirim transaksi', () async {
    final records = <anchor.AnchorRecord>[];
    final store = _MemoryStore(records, 'u1');
    final genesis = Blockchain.genesis();
    final chain = [genesis];
    var serviceCalls = 0;

    final coordinator = AnchorCoordinator(
      null,
      rpcConfigured: true,
      readChain: () => chain,
      service: () {
        serviceCalls++;
        throw StateError('no');
      },
      store: () => store,
      currentUserId: () => 'u1',
      listenConnectivity: false,
    );

    await coordinator.ensureAnchored();
    expect(serviceCalls, 0);
    expect(records, isEmpty);
  });

  test('satu stamp mengirim sekali', () async {
    final records = <anchor.AnchorRecord>[];
    final store = _MemoryStore(records, 'u1');
    final genesis = Blockchain.genesis();
    final stamp = Blockchain.next([genesis], 'stamp', {'club': 'a'}, 'owner');
    final chain = [genesis, stamp];
    var serviceCalls = 0;

    final coordinator = AnchorCoordinator(
      null,
      rpcConfigured: true,
      readChain: () => chain,
      service: () {
        serviceCalls++;
        return anchor.ChainAnchorService(
          client: _TestClient(),
          wallet: _TestWallet(EthPrivateKey.createRandom(Random.secure())),
          rpcUrl: AppConfig.sepoliaRpcUrl.isEmpty
              ? 'https://sepolia.invalid'
              : AppConfig.sepoliaRpcUrl,
          receiptTimeout: Duration.zero,
          pollInterval: Duration.zero,
          delay: (_) async {},
        );
      },
      store: () => store,
      currentUserId: () => 'u1',
      listenConnectivity: false,
    );

    await coordinator.ensureAnchored();
    expect(serviceCalls, 1);
    expect(records.length, 1);
    expect(records.first.headHash, stamp.hash);
  });

  test('anchor sukses menyegarkan anchorsProvider, stampProof, dan saldo',
      () async {
    final genesis = Blockchain.genesis();
    final stamp = Blockchain.next([genesis], 'stamp', {'club': 'a'}, 'owner');
    final chain = [genesis, stamp];
    final records = <anchor.AnchorRecord>[];
    final store = _MemoryStore(records, 'u1');
    final client = _TestClient()..balance = BigInt.from(10);
    final wallet = _TestWallet(EthPrivateKey.createRandom(Random.secure()));
    final container = _providerContainer(
      store: store,
      chain: chain,
      client: client,
      wallet: wallet,
    );
    addTearDown(container.dispose);

    expect(await container.read(walletBalanceProvider.future), BigInt.from(10));
    expect(container.read(anchorsProvider), isEmpty);
    expect(
      container.read(stampProofProvider(stamp)).kind,
      StampProofKind.none,
    );

    client.balance = BigInt.parse('50000000000000000');

    await container.read(anchorCoordinatorProvider.notifier).ensureAnchored();

    final anchors = container.read(anchorsProvider);
    expect(anchors, hasLength(1));
    expect(anchors.single.headHash, stamp.hash);
    expect(anchors.single.status, anchor.AnchorStatus.confirmed);
    expect(
      container.read(stampProofProvider(stamp)).kind,
      StampProofKind.confirmed,
    );
    expect(await container.read(walletBalanceProvider.future), client.balance);
  });

  test('refresh pending menjadi confirmed memperbarui anchorsProvider',
      () async {
    final genesis = Blockchain.genesis();
    final stamp = Blockchain.next([genesis], 'stamp', {'club': 'a'}, 'owner');
    final chain = [genesis, stamp];
    final records = <anchor.AnchorRecord>[_record(stamp)];
    final store = _MemoryStore(records, 'u1');
    final client = _TestClient()..receiptStatus = anchor.EthTxStatus.success;
    final wallet = _TestWallet(EthPrivateKey.createRandom(Random.secure()));
    final container = _providerContainer(
      store: store,
      chain: chain,
      client: client,
      wallet: wallet,
    );
    addTearDown(container.dispose);

    expect(
      container.read(anchorsProvider).single.status,
      anchor.AnchorStatus.pending,
    );
    expect(
      container.read(stampProofProvider(stamp)).kind,
      StampProofKind.pending,
    );

    await container.read(anchorCoordinatorProvider.notifier).ensureAnchored();

    expect(
      container.read(anchorsProvider).single.status,
      anchor.AnchorStatus.confirmed,
    );
    expect(
      container.read(stampProofProvider(stamp)).kind,
      StampProofKind.confirmed,
    );
  });
}

ProviderContainer _providerContainer({
  required _MemoryStore store,
  required List<Block> chain,
  required _TestClient client,
  required _TestWallet wallet,
  String userId = 'u1',
}) =>
    ProviderContainer(
      overrides: [
        anchorStoreProvider.overrideWithValue(store),
        walletAddressProvider.overrideWith((ref) async => wallet.address),
        anchorAddressProvider.overrideWith((ref) async => wallet.address),
        ethClientProvider.overrideWithValue(client),
        anchorCoordinatorProvider.overrideWith(
          (ref) => AnchorCoordinator(
            ref,
            rpcConfigured: true,
            readChain: () => chain,
            service: () => anchor.ChainAnchorService(
              client: client,
              wallet: wallet,
              rpcUrl: 'https://sepolia.invalid',
              receiptTimeout: Duration.zero,
              pollInterval: Duration.zero,
              delay: (_) async {},
            ),
            store: () => store,
            currentUserId: () => userId,
            listenConnectivity: false,
          ),
        ),
      ],
    );

class _TestClient implements anchor.EthClient {
  BigInt balance = BigInt.from(1000000);
  anchor.EthTxStatus receiptStatus = anchor.EthTxStatus.success;

  @override
  Future<int> getChainId() async => AppConfig.sepoliaChainId;

  @override
  Future<BigInt> getBalanceWei(String address) async => balance;

  @override
  Future<String> sendDataTransaction(
    dynamic credentials,
    String utf8Payload,
    String to,
  ) async =>
      '0xabc';

  @override
  Future<String?> getTransactionInputUtf8(String txHash) async => null;

  @override
  Future<anchor.EthTxStatus> getReceiptStatus(String txHash) async =>
      receiptStatus;
}

class _TestWallet extends WalletRepository {
  _TestWallet(this._credentials)
      : super(const FlutterSecureStorage(), () => 'u1');

  final EthPrivateKey _credentials;

  String get address => _credentials.address.hexEip55;

  @override
  Future<String> getOrCreateAddress() async => _credentials.address.hexEip55;

  @override
  Future<EthPrivateKey> credentials() async => _credentials;
}
