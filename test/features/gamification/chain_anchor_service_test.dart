import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/utils/app_config.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_anchor_service.dart';
import 'package:ultimate_fanzone/features/gamification/data/wallet_repository.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

const _txHash =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class _FakeEthClient implements EthClient {
  _FakeEthClient({
    this.chainIdValue = AppConfig.sepoliaChainId,
    BigInt? balance,
  }) : balance = balance ?? BigInt.from(1000);

  int chainIdValue;
  BigInt balance;
  EthTxStatus receiptStatus = EthTxStatus.success;
  final List<EthTxStatus> receiptSequence = [];
  String? txInput;
  Object? error;

  int getChainIdCalls = 0;
  int sendCalls = 0;
  int balanceCalls = 0;
  EthPrivateKey? sentCredentials;
  String? sentPayload;
  String? sentTo;
  String? balanceAddress;

  @override
  Future<int> getChainId() async {
    if (error != null) throw error!;
    getChainIdCalls++;
    return chainIdValue;
  }

  @override
  Future<BigInt> getBalanceWei(String address) async {
    if (error != null) throw error!;
    balanceCalls++;
    balanceAddress = address;
    return balance;
  }

  @override
  Future<String> sendDataTransaction(
    EthPrivateKey credentials,
    String utf8Payload,
    String to,
  ) async {
    if (error != null) throw error!;
    sendCalls++;
    sentCredentials = credentials;
    sentPayload = utf8Payload;
    sentTo = to;
    return _txHash;
  }

  @override
  Future<String?> getTransactionInputUtf8(String txHash) async {
    if (error != null) throw error!;
    return txInput;
  }

  @override
  Future<EthTxStatus> getReceiptStatus(String txHash) async {
    if (error != null) throw error!;
    if (receiptSequence.isNotEmpty) return receiptSequence.removeAt(0);
    return receiptStatus;
  }
}

class _FakeWallet extends WalletRepository {
  _FakeWallet(this.credentialsKey)
      : super(const FlutterSecureStorage(), () => 'test-user');

  final EthPrivateKey credentialsKey;

  @override
  Future<String> getOrCreateAddress() async => credentialsKey.address.hexEip55;

  @override
  Future<EthPrivateKey> credentials() async => credentialsKey;
}

void main() {
  const rpcUrl = 'https://sepolia.invalid';
  const timeout = Duration.zero;
  late EthPrivateKey credentials;
  late _FakeWallet wallet;
  late List<Block> chain;

  setUpAll(() {
    credentials = EthPrivateKey.createRandom(Random.secure());
    wallet = _FakeWallet(credentials);
    final genesis = Blockchain.genesis();
    chain = [
      genesis,
      Blockchain.next(
          [genesis],
          'stamp',
          {
            'club': 'arsenal',
            'stadium': 'Emirates',
          },
          'owner-a'),
    ];
  });

  ChainAnchorService service(
    _FakeEthClient client, {
    String url = rpcUrl,
    Duration receiptTimeout = timeout,
    Future<void> Function(Duration)? delay,
  }) =>
      ChainAnchorService(
        client: client,
        wallet: wallet,
        rpcUrl: url,
        receiptTimeout: receiptTimeout,
        pollInterval: Duration.zero,
        delay: delay ?? (_) async {},
      );

  test('menolak rantai lokal yang tidak valid', () async {
    final client = _FakeEthClient();
    await expectLater(
      service(client).anchor(const []),
      throwsA(isA<AnchorException>()
          .having((e) => e.failure, 'failure', AnchorFailure.invalidChain)),
    );
    expect(client.sendCalls, 0);
  });

  test('RPC kosong -> NotConfigured tanpa memanggil klien', () async {
    final client = _FakeEthClient();
    await expectLater(
      service(client, url: '').anchor(chain),
      throwsA(isA<AnchorException>()
          .having((e) => e.failure, 'failure', AnchorFailure.notConfigured)),
    );
    expect(client.getChainIdCalls, 0);
    expect(client.sendCalls, 0);
  });

  test('chain id selain Sepolia ditolak tanpa mengirim transaksi', () async {
    final client = _FakeEthClient(chainIdValue: 1);
    await expectLater(
      service(client).anchor(chain),
      throwsA(isA<AnchorException>()
          .having((e) => e.failure, 'failure', AnchorFailure.wrongNetwork)),
    );
    expect(client.sendCalls, 0);
  });

  test('saldo nol -> InsufficientFunds tanpa mengirim transaksi', () async {
    final client = _FakeEthClient(balance: BigInt.zero);
    await expectLater(
      service(client).anchor(chain),
      throwsA(isA<AnchorException>().having(
          (e) => e.failure, 'failure', AnchorFailure.insufficientFunds)),
    );
    expect(client.getChainIdCalls, 1);
    expect(client.balanceCalls, 1);
    expect(client.sendCalls, 0);
  });

  test('sukses memakai payload UFZ1:<headHash> dan mengembalikan record',
      () async {
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.success;
    final record = await service(client).anchor(chain);

    expect(client.sendCalls, 1);
    expect(client.sentPayload, 'UFZ1:${chain.last.hash}');
    expect(client.sentCredentials?.address, credentials.address);
    expect(client.sentTo, credentials.address.hexEip55);
    expect(client.balanceAddress, credentials.address.hexEip55);
    expect(record.txHash, _txHash);
    expect(record.headHash, chain.last.hash);
    expect(record.headIndex, chain.last.index);
    expect(record.chainLength, chain.length);
    expect(record.status, AnchorStatus.confirmed);
    expect(record.explorerUrl, '${AppConfig.explorerBase}/tx/${record.txHash}');
  });

  test('receipt timeout mengembalikan record pending, bukan melempar',
      () async {
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.pending;
    final record = await service(client).anchor(chain);

    expect(record.status, AnchorStatus.pending);
    expect(client.sendCalls, 1);
  });

  test('receipt gagal/revert -> typed failure', () async {
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.failed;
    await expectLater(
      service(client).anchor(chain),
      throwsA(isA<AnchorException>()
          .having((e) => e.failure, 'failure', AnchorFailure.reverted)),
    );
  });

  test('refreshStatus: pending -> confirmed', () async {
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.success;
    final record = _record(chain.last, status: AnchorStatus.pending);

    final refreshed = await service(client).refreshStatus(record);

    expect(refreshed.status, AnchorStatus.confirmed);
  });

  test('refreshStatus: error membiarkan status pending dan tidak melempar',
      () async {
    final client = _FakeEthClient()..error = Exception('jaringan putus');
    final record = _record(chain.last, status: AnchorStatus.pending);

    final refreshed = await service(client).refreshStatus(record);

    expect(refreshed.status, AnchorStatus.pending);
    expect(refreshed.txHash, record.txHash);
  });

  test('verify: semua hasil enum', () async {
    final client = _FakeEthClient();
    final anchorService = service(client);
    final record = _record(chain.last);

    client.txInput = 'UFZ1:${chain.last.hash}';
    expect(
      await anchorService.verify(record, chain),
      AnchorVerifyResult.verified,
    );

    expect(
      await anchorService.verify(
        _record(chain.last, status: AnchorStatus.pending),
        chain,
      ),
      AnchorVerifyResult.pending,
    );

    client.txInput = 'UFZ1:hash-lain';
    expect(
      await anchorService.verify(record, chain),
      AnchorVerifyResult.mismatch,
    );

    client.txInput = null;
    expect(
      await anchorService.verify(record, chain),
      AnchorVerifyResult.notFound,
    );

    client.error = Exception('rpc error');
    expect(
      await anchorService.verify(record, chain),
      AnchorVerifyResult.networkError,
    );
  });

  test('verify: input cocok tetapi blok lokal berbeda -> localChainDiverged',
      () async {
    final client = _FakeEthClient()..txInput = 'UFZ1:${chain.last.hash}';
    final alternative = [
      chain.first,
      Blockchain.next(
          [chain.first],
          'stamp',
          {
            'club': 'chelsea',
            'stadium': 'Bridge',
          },
          'owner-b'),
    ];

    expect(
      await service(client).verify(_record(chain.last), alternative),
      AnchorVerifyResult.localChainDiverged,
    );
  });

  test('verify: rantai lokal tidak valid -> localChainDiverged', () async {
    final client = _FakeEthClient()..txInput = 'UFZ1:${chain.last.hash}';

    expect(
      await service(client).verify(_record(chain.last), const []),
      AnchorVerifyResult.localChainDiverged,
    );
  });

  test('anchor/verify/refreshStatus tidak mengubah rantai atau owner',
      () async {
    final before = chain.map((block) => block.toJson()).toList();
    final ownersBefore = chain.map((block) => block.owner).toList();
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.success;
    final anchorService = service(client);

    final record = await anchorService.anchor(chain);
    client.txInput = 'UFZ1:${chain.last.hash}';
    expect(
      await anchorService.verify(record, chain),
      AnchorVerifyResult.verified,
    );
    await anchorService.refreshStatus(
      _record(chain.last, status: AnchorStatus.pending),
    );

    expect(chain.map((block) => block.toJson()).toList(), before);
    expect(chain.map((block) => block.owner).toList(), ownersBefore);
  });

  test('anchor memakai alamat dan kredensial jangkar bersama', () async {
    final sharedKey = EthPrivateKey.createRandom(Random.secure());
    final sharedAddress = sharedKey.address.hexEip55;
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.success;
    var keyHex = bytesToHex(sharedKey.privateKey);
    if (keyHex.startsWith('0x')) keyHex = keyHex.substring(2);
    final sharedWallet = WalletRepository(
      const FlutterSecureStorage(),
      () => 'user-a',
      anchorPrivateKey: keyHex,
    );
    final anchorService = ChainAnchorService(
      client: client,
      wallet: sharedWallet,
      rpcUrl: rpcUrl,
      receiptTimeout: timeout,
      pollInterval: Duration.zero,
      delay: (_) async {},
    );

    final record = await anchorService.anchor(chain);

    expect(client.balanceAddress, sharedAddress);
    expect(client.sentTo, sharedAddress);
    expect(client.sentCredentials?.address, sharedKey.address);
    expect(client.sentPayload, 'UFZ1:${chain.last.hash}');
    expect(Web3EthClient.chainId, 11155111);
    expect(record.status, AnchorStatus.confirmed);

    final transaction = Web3EthClient(rpcUrl: '').buildAnchorTransaction(
      EthereumAddress.fromHex(sharedAddress),
      Uint8List.fromList(utf8.encode(client.sentPayload!)),
    );
    expect(transaction.to, EthereumAddress.fromHex(sharedAddress));
    expect(transaction.value?.getInWei, BigInt.zero);
    expect(
        transaction.data, Uint8List.fromList(utf8.encode(client.sentPayload!)));
  });

  test('sumber kredensial dan alamat dapat disuntikkan untuk test', () async {
    final sharedKey = EthPrivateKey.createRandom(Random.secure());
    final sharedAddress = sharedKey.address.hexEip55;
    final client = _FakeEthClient()..receiptStatus = EthTxStatus.success;
    final anchorService = ChainAnchorService(
      client: client,
      wallet: wallet,
      rpcUrl: rpcUrl,
      receiptTimeout: timeout,
      pollInterval: Duration.zero,
      delay: (_) async {},
      credentials: () async => sharedKey,
      address: () async => sharedAddress,
    );

    await anchorService.anchor(chain);

    expect(client.balanceAddress, sharedAddress);
    expect(client.sentTo, sharedAddress);
    expect(client.sentCredentials?.address, sharedKey.address);
  });

  test('AnchorRecord toJson/fromJson toleran terhadap field yang hilang', () {
    final record = _record(chain.last);
    final decoded = AnchorRecord.fromJson(record.toJson());
    expect(decoded.txHash, record.txHash);
    expect(decoded.headHash, record.headHash);
    expect(decoded.status, AnchorStatus.confirmed);

    final tolerant = AnchorRecord.fromJson(const {});
    expect(tolerant.txHash, '');
    expect(tolerant.headHash, '');
    expect(tolerant.status, AnchorStatus.pending);
  });

  test('Web3EthClient membangun transaksi value 0 ke alamat sendiri', () {
    final client = Web3EthClient(rpcUrl: '');
    final data = Uint8List.fromList(utf8.encode('UFZ1:abc'));
    final transaction =
        client.buildAnchorTransaction(credentials.address, data);

    expect(transaction.to, credentials.address);
    expect(transaction.value?.getInWei, BigInt.zero);
    expect(transaction.data, data);
    expect(Web3EthClient.chainId, AppConfig.sepoliaChainId);
    client.dispose();
  });
}

AnchorRecord _record(Block head,
    {AnchorStatus status = AnchorStatus.confirmed}) {
  const txHash = _txHash;
  return AnchorRecord(
    txHash: txHash,
    headHash: head.hash,
    headIndex: head.index,
    chainLength: head.index + 1,
    createdAtMs: 1700000000000,
    explorerUrl: AppConfig.explorerTxUrl(txHash),
    status: status,
  );
}
