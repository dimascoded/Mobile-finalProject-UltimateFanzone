import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import 'chain_anchor_service.dart';

/// Dompet Web3 per pengguna untuk identitas dan anchor rantai paspor.
///
/// Private key disimpan di secure storage dengan kunci ber-sufiks user id
/// (`wallet_private_key_<userId>`), sehingga dua akun di perangkat yang sama
/// tidak berbagi dompet. Kunci ini SENGAJA tidak dihapus saat logout karena
/// menyimpan dana testnet; akun berikutnya tetap membaca kuncinya sendiri.
///
/// Kunci lama tanpa sufiks (`wallet_private_key`) dimigrasikan ke kunci
/// ber-sufiks pengguna yang sedang masuk lalu dihapus. Tanpa pengguna aktif,
/// repository tidak pernah membuat kunci tanpa sufiks dan melempar
/// [StateError]. Private key tidak pernah di-log, ditampilkan, disalin ke
/// Hive/Supabase, atau dimasukkan ke pesan galat.
class WalletRepository {
  WalletRepository(
    this._storage,
    this._currentUserId, {
    String? anchorPrivateKey,
  }) : _anchorPrivateKey = anchorPrivateKey ?? AppConfig.anchorPrivateKey;

  final FlutterSecureStorage _storage;
  final String? Function() _currentUserId;
  final String _anchorPrivateKey;

  /// Basis kunci secure storage; kunci sebenarnya selalu ber-sufiks user id.
  static const baseKey = 'wallet_private_key';

  /// Pesan statis untuk kunci anchor bersama yang tidak valid.
  static const invalidAnchorKeyMessage =
      'Kunci anchor bersama tidak valid. Hubungi dukungan.';

  static final _anchorKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Nilai key per pengguna, mengikuti pola `base_<userId>` milik AuthRepository.
  static String keyFor(String userId) => '${baseKey}_$userId';

  String _requireUserId() {
    final userId = _currentUserId();
    if (userId == null || userId.trim().isEmpty) {
      throw StateError('Pengguna belum masuk; dompet tidak tersedia.');
    }
    return userId;
  }

  /// Baca kunci scoped, migrasikan kunci legacy sekali, lalu hapus legacy.
  ///
  /// Tidak pernah membuat kunci baru; pemanggil yang memutuskan apakah perlu
  /// membuat dompet. Kunci legacy hanya boleh diadopsi setelah ada user id.
  Future<String?> _readScopedKey(String userId) async {
    final scopedKey = keyFor(userId);
    var hex = await _storage.read(key: scopedKey);
    final legacy = await _storage.read(key: baseKey);
    if (hex == null && legacy != null) {
      hex = legacy;
      await _storage.write(key: scopedKey, value: legacy);
    }
    if (legacy != null) {
      await _storage.delete(key: baseKey);
    }
    return hex;
  }

  EthPrivateKey _decode(String hex) {
    try {
      return EthPrivateKey.fromHex(hex);
    } catch (_) {
      throw StateError('Kunci dompet tidak valid. Hubungi dukungan.');
    }
  }

  /// Buat wallet per pengguna sekali saja; panggilan berulang mengembalikan
  /// alamat yang sama dalam bentuk checksum EIP-55.
  Future<String> getOrCreateAddress() async {
    final userId = _requireUserId();
    var hex = await _readScopedKey(userId);
    if (hex == null) {
      final key = EthPrivateKey.createRandom(Random.secure());
      hex = bytesToHex(key.privateKey);
      // Strip '0x' prefix if present to ensure consistent 64-char hex storage
      if (hex.startsWith('0x')) hex = hex.substring(2);
      await _storage.write(key: keyFor(userId), value: hex);
    }
    return _decode(hex).address.hexEip55;
  }

  /// Kredensial untuk menandatangani transaksi anchor. Hanya dipakai
  /// [ChainAnchorService] dan tidak pernah diekspos ke UI/log.
  Future<EthPrivateKey> credentials() async {
    final userId = _requireUserId();
    final hex = await _readScopedKey(userId);
    if (hex == null) {
      throw StateError('Dompet belum dibuat untuk pengguna ini.');
    }
    return _decode(hex);
  }

  /// Kredensial dompet jangkar bersama dari `ANCHOR_PRIVATE_KEY`.
  ///
  /// Kunci hanya dibaca dari konfigurasi build dan tidak pernah disimpan ke
  /// secure storage, Hive, Supabase, atau file. Bila kunci kosong, perilaku
  /// kembali ke dompet per pengguna seperti sebelum fitur jangkar bersama ada.
  Future<EthPrivateKey> anchorCredentials() async {
    if (_anchorPrivateKey.isEmpty) return credentials();
    return _decodeAnchorKey(_anchorPrivateKey);
  }

  /// Alamat dompet jangkar bersama (checksum EIP-55).
  ///
  /// Tanpa kunci bersama, alamat ini sama dengan alamat dompet per pengguna.
  Future<String> anchorAddress() async {
    if (_anchorPrivateKey.isEmpty) return getOrCreateAddress();
    return _decodeAnchorKey(_anchorPrivateKey).address.hexEip55;
  }

  EthPrivateKey _decodeAnchorKey(String raw) {
    final hex = raw.startsWith('0x') ? raw.substring(2) : raw;
    if (!_anchorKeyPattern.hasMatch(hex)) {
      throw const AnchorException(
        AnchorFailure.notConfigured,
        invalidAnchorKeyMessage,
      );
    }
    try {
      return EthPrivateKey.fromHex(hex);
    } catch (_) {
      throw const AnchorException(
        AnchorFailure.notConfigured,
        invalidAnchorKeyMessage,
      );
    }
  }
}

/// Penyedia [WalletRepository] yang memakai secure storage bersama dan user id
/// dari sesi Supabase aktif.
final walletRepositoryProvider = Provider((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return WalletRepository(
    ref.watch(secureStorageProvider),
    () => auth.currentUserId,
  );
});
