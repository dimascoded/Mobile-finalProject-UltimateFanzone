import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_anchor_service.dart';
import 'package:ultimate_fanzone/features/gamification/data/wallet_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class _RecordingEthClient implements EthClient {
  String? lastAddress;

  @override
  Future<BigInt> getBalanceWei(String address) async {
    lastAddress = address;
    return BigInt.from(42);
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

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('dua user id mendapat dua alamat berbeda dan kunci terpisah', () async {
    const storage = FlutterSecureStorage();
    var userId = 'user-a';
    final repo = WalletRepository(storage, () => userId);

    final addressA = await repo.getOrCreateAddress();
    userId = 'user-b';
    final addressB = await repo.getOrCreateAddress();

    expect(addressA, isNot(addressB));
    expect(
        await storage.read(key: WalletRepository.keyFor('user-a')), isNotNull);
    expect(
        await storage.read(key: WalletRepository.keyFor('user-b')), isNotNull);
    expect(await storage.read(key: WalletRepository.baseKey), isNull);
  });

  test('tanpa user id melempar StateError tanpa membuat kunci global',
      () async {
    const storage = FlutterSecureStorage();
    final repo = WalletRepository(storage, () => null);

    await expectLater(repo.getOrCreateAddress(), throwsStateError);
    await expectLater(repo.credentials(), throwsStateError);
    expect(await storage.read(key: WalletRepository.baseKey), isNull);
    expect(await storage.read(key: WalletRepository.keyFor('user-a')), isNull);
  });

  test('kunci legacy tanpa sufiks dimigrasikan lalu dihapus', () async {
    final key = EthPrivateKey.createRandom(Random.secure());
    final hex = bytesToHex(key.privateKey);
    FlutterSecureStorage.setMockInitialValues({
      WalletRepository.baseKey: hex,
    });
    const storage = FlutterSecureStorage();
    final repo = WalletRepository(storage, () => 'user-a');

    final address = await repo.getOrCreateAddress();

    expect(address, key.address.hexEip55);
    expect(await storage.read(key: WalletRepository.keyFor('user-a')), hex);
    expect(await storage.read(key: WalletRepository.baseKey), isNull);
  });

  test('private key tidak pernah muncul di toString atau pesan galat',
      () async {
    const storage = FlutterSecureStorage();
    final repo = WalletRepository(storage, () => 'user-a');
    await repo.getOrCreateAddress();
    final credentials = await repo.credentials();
    final keyHex = bytesToHex(credentials.privateKey);

    expect(keyHex, isNotEmpty);
    expect(repo.toString(), isNot(contains(keyHex)));
    expect(credentials.toString(), isNot(contains(keyHex)));

    const brokenSecret = 'bukan-private-key-rahasia-123';
    await storage.write(
      key: WalletRepository.keyFor('user-b'),
      value: brokenSecret,
    );
    final brokenRepo = WalletRepository(storage, () => 'user-b');
    try {
      await brokenRepo.getOrCreateAddress();
      fail('kunci rusak seharusnya melempar');
    } catch (error) {
      expect(error.toString(), isNot(contains(brokenSecret)));
      expect(error.toString(), isNot(contains(keyHex)));
    }
  });

  test('kunci jangkar bersama memberi alamat sama untuk dua user', () async {
    const storage = FlutterSecureStorage();
    final key = EthPrivateKey.createRandom(Random.secure());
    var keyHex = bytesToHex(key.privateKey);
    if (keyHex.startsWith('0x')) keyHex = keyHex.substring(2);
    var userId = 'user-a';
    final repo = WalletRepository(
      storage,
      () => userId,
      anchorPrivateKey: keyHex,
    );
    final container = ProviderContainer(
      overrides: [walletRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final userAddressA = await container.read(walletAddressProvider.future);
    final anchorA = await container.read(anchorAddressProvider.future);

    userId = 'user-b';
    container.invalidate(walletAddressProvider);
    container.invalidate(anchorAddressProvider);
    final userAddressB = await container.read(walletAddressProvider.future);
    final anchorB = await container.read(anchorAddressProvider.future);

    expect(anchorA, key.address.hexEip55);
    expect(anchorB, anchorA);
    expect(userAddressA, isNot(userAddressB));
  });

  test('kunci jangkar kosong memakai dompet per pengguna', () async {
    const storage = FlutterSecureStorage();
    final repo = WalletRepository(
      storage,
      () => 'user-a',
      anchorPrivateKey: '',
    );

    final address = await repo.getOrCreateAddress();
    final anchorAddress = await repo.anchorAddress();
    final credentials = await repo.credentials();
    final anchorCredentials = await repo.anchorCredentials();

    expect(anchorAddress, address);
    expect(anchorCredentials.address, credentials.address);
    expect(anchorCredentials.privateKey, credentials.privateKey);
  });

  test('kunci jangkar tidak valid tidak membocorkan isi kunci', () async {
    const storage = FlutterSecureStorage();
    final invalidKeys = <String>[
      'rahasia-jangkar',
      '0x1234',
      'a' * 63,
      '0x${'g' * 64}',
    ];

    for (final invalid in invalidKeys) {
      final repo = WalletRepository(
        storage,
        () => 'user-a',
        anchorPrivateKey: invalid,
      );

      try {
        await repo.anchorAddress();
        fail('kunci tidak valid seharusnya melempar');
      } on AnchorException catch (error) {
        expect(error.failure, AnchorFailure.notConfigured);
        expect(error.message, WalletRepository.invalidAnchorKeyMessage);
        expect(error.toString(), isNot(contains(invalid)));
        expect(
          error.toString(),
          isNot(contains(invalid.replaceFirst('0x', ''))),
        );
      }

      try {
        await repo.anchorCredentials();
        fail('kunci tidak valid seharusnya melempar');
      } on AnchorException catch (error) {
        expect(error.failure, AnchorFailure.notConfigured);
        expect(error.message, WalletRepository.invalidAnchorKeyMessage);
        expect(error.toString(), isNot(contains(invalid)));
      }
    }
  });

  test('kunci jangkar tidak ditulis dan saldo membaca alamat jangkar',
      () async {
    const storage = FlutterSecureStorage();
    final key = EthPrivateKey.createRandom(Random.secure());
    var keyHex = bytesToHex(key.privateKey);
    if (keyHex.startsWith('0x')) keyHex = keyHex.substring(2);
    expect(keyHex.length, 64);
    expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(keyHex), isTrue);
    final repo = WalletRepository(
      storage,
      () => 'user-a',
      anchorPrivateKey: keyHex,
    );
    final client = _RecordingEthClient();
    final container = ProviderContainer(
      overrides: [
        walletRepositoryProvider.overrideWithValue(repo),
        ethClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);

    final balance = await container.read(walletBalanceProvider.future);

    expect(balance, BigInt.from(42));
    expect(client.lastAddress, key.address.hexEip55);
    final stored = await storage.readAll();
    expect(stored.values, isNot(contains(keyHex)));
    expect(stored.values, isNot(contains('0x$keyHex')));
    expect(await storage.read(key: WalletRepository.baseKey), isNull);
  });
}
