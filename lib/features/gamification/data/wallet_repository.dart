import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import '../../auth/data/auth_repository.dart';

class WalletRepository {
  WalletRepository(this._storage);
  final FlutterSecureStorage _storage;
  static const _pkKey = 'wallet_private_key';

  /// Buat wallet sekali saja; private key disimpan permanen di secure storage.
  Future<String> getOrCreateAddress() async {
    var hex = await _storage.read(key: _pkKey);
    if (hex == null) {
      final key = EthPrivateKey.createRandom(Random.secure());
      hex = bytesToHex(key.privateKey);
      await _storage.write(key: _pkKey, value: hex);
    }
    return EthPrivateKey.fromHex(hex).address.hexEip55;
  }
}

final walletRepositoryProvider =
    Provider((ref) => WalletRepository(ref.watch(secureStorageProvider)));
