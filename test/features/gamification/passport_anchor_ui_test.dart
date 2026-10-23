import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/core/utils/app_config.dart';
import 'package:ultimate_fanzone/core/utils/external_launcher.dart';
import 'package:ultimate_fanzone/features/auth/data/identity_store.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/gamification/data/anchor_store.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_anchor_service.dart'
    as anchor;
import 'package:ultimate_fanzone/features/gamification/data/wallet_repository.dart';
import 'package:ultimate_fanzone/features/gamification/domain/club_card.dart';
import 'package:ultimate_fanzone/features/gamification/presentation/passport_screen.dart';
import 'package:ultimate_fanzone/features/gamification/providers/anchor_coordinator.dart';
import 'package:ultimate_fanzone/features/gamification/providers/card_collection_provider.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:web3dart/web3dart.dart';

class _MemoryIdentityStore implements IdentityStore {
  final _values = <String, String>{};

  @override
  String? get(String key) => _values[key];

  @override
  Future<void> put(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _MemoryStore extends AnchorStore {
  _MemoryStore(this._records, String userId)
      : super(_MemoryIdentityStore(), () => userId);

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

class _TestClient implements anchor.EthClient {
  BigInt balance = BigInt.zero;
  anchor.EthTxStatus receiptStatus = anchor.EthTxStatus.success;
  Completer<String>? sendGate;

  @override
  Future<int> getChainId() async => AppConfig.sepoliaChainId;

  @override
  Future<BigInt> getBalanceWei(String address) async => balance;

  @override
  Future<String> sendDataTransaction(
    EthPrivateKey credentials,
    String utf8Payload,
    String to,
  ) {
    final gate = sendGate;
    return gate == null ? Future.value('0xabc') : gate.future;
  }

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
  Future<String> getOrCreateAddress() async => address;

  @override
  Future<EthPrivateKey> credentials() async => _credentials;
}

const _arsenal = PlClub(
  key: 'arsenal',
  name: 'Arsenal',
  shortName: 'Arsenal',
  tla: 'ARS',
  city: 'London',
  stadium: 'Emirates',
  lat: 0,
  lng: 0,
  color: 0xFFEF0107,
  aliases: ['Arsenal'],
);

Widget _app({
  required Widget home,
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: home,
      ),
    );

List<Override> _overrides({
  required _MemoryStore store,
  required List<Block> chain,
  required List<Block> stamps,
  required _TestClient client,
  required _TestWallet wallet,
  String? anchorAddress,
}) =>
    [
      favoriteClubProvider.overrideWithValue(_arsenal),
      clubCrestProvider.overrideWithValue(const {}),
      chainValidProvider.overrideWithValue(true),
      stampsProvider.overrideWithValue(stamps),
      ownedClubsProvider.overrideWithValue(const <String>{}),
      cardCollectionProvider.overrideWithValue(const <ClubCard>[]),
      stampDistanceProvider.overrideWith((ref) => Future<int?>.value(null)),
      walletAddressProvider.overrideWith((ref) async => wallet.address),
      anchorAddressProvider.overrideWith(
        (ref) async => anchorAddress ?? wallet.address,
      ),
      ethClientProvider.overrideWithValue(client),
      anchorStoreProvider.overrideWithValue(store),
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
          currentUserId: () => 'u1',
          listenConnectivity: false,
        ),
      ),
    ];

void main() {
  testWidgets(
    'stamp chip berubah dan Coba lagi hilang setelah anchor selesai',
    (tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final genesis = Blockchain.genesis();
      final stamp = Blockchain.next(
        [genesis],
        'stamp',
        {'club': 'arsenal', 'stadium': 'Emirates'},
        'owner',
      );
      final chain = [genesis, stamp];
      final store = _MemoryStore(<anchor.AnchorRecord>[], 'u1');
      final client = _TestClient()..balance = BigInt.from(1000000);
      final gate = Completer<String>();
      client.sendGate = gate;
      final wallet = _TestWallet(EthPrivateKey.createRandom(Random.secure()));

      await tester.pumpWidget(
        _app(
          home: const PassportScreen(),
          overrides: _overrides(
            store: store,
            chain: chain,
            stamps: [stamp],
            client: client,
            wallet: wallet,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Belum dijangkarkan'), findsOneWidget);

      gate.complete('0xabc');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Terbukti di Sepolia'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    },
  );

  testWidgets(
    'teks saldo diperbarui setelah ikon refresh ditekan',
    (tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final genesis = Blockchain.genesis();
      final client = _TestClient();
      final store = _MemoryStore(<anchor.AnchorRecord>[], 'u1');
      final wallet = _TestWallet(EthPrivateKey.createRandom(Random.secure()));

      await tester.pumpWidget(
        _app(
          home: const PassportScreen(),
          overrides: _overrides(
            store: store,
            chain: [genesis],
            stamps: const <Block>[],
            client: client,
            wallet: wallet,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('0 ETH'), findsOneWidget);

      client.balance = BigInt.parse('50000000000000000');
      await tester.tap(find.byTooltip('Perbarui saldo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('0.05 ETH'), findsOneWidget);
    },
  );

  testWidgets(
    'kartu dompet menampilkan alamat jangkar bersama dan Etherscan membuka tautannya',
    (tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final shared =
          EthPrivateKey.createRandom(Random.secure()).address.hexEip55;
      final genesis = Blockchain.genesis();
      final client = _TestClient()..balance = BigInt.from(1000000);
      final store = _MemoryStore(<anchor.AnchorRecord>[], 'u1');
      final wallet = _TestWallet(EthPrivateKey.createRandom(Random.secure()));
      final opened = <Uri>[];

      await tester.pumpWidget(
        _app(
          home: const PassportScreen(),
          overrides: [
            ..._overrides(
              store: store,
              chain: [genesis],
              stamps: const <Block>[],
              client: client,
              wallet: wallet,
              anchorAddress: shared,
            ),
            externalLauncherProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final short =
          '${shared.substring(0, 6)}\u2026${shared.substring(shared.length - 4)}';
      expect(find.text('Dompet jangkar (bersama)'), findsOneWidget);
      expect(find.text(short), findsOneWidget);

      await tester.tap(find.text('Cek di Sepolia Etherscan'));
      await tester.pump();

      expect(opened, hasLength(1));
      expect(
        opened.single.toString(),
        '${AppConfig.explorerBase}/address/$shared',
      );
    },
  );
}
