import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// http adalah dependensi transitif web3dart (Web3Client membutuhkannya).
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../../../core/utils/app_config.dart';
import 'blockchain.dart';
import 'wallet_repository.dart';

/// Status transaksi yang dibaca dari receipt Ethereum.
enum EthTxStatus { pending, success, failed }

/// Status tersimpan sebuah anchor.
enum AnchorStatus { pending, confirmed }

/// Jenis kegagalan anchor yang bisa ditangani pemanggil tanpa parsing teks.
enum AnchorFailure {
  notConfigured,
  invalidChain,
  wrongNetwork,
  insufficientFunds,
  network,
  rejected,
  reverted,
}

/// Galat anchor dengan tipe stabil dan pesan aman.
///
/// Pesan tidak pernah memuat URL RPC, private key, payload, atau detail RPC
/// mentah. Pemanggil sebaiknya memilih teks UI berdasarkan [failure].
class AnchorException implements Exception {
  const AnchorException(this.failure, [this.message = '']);

  final AnchorFailure failure;
  final String message;

  @override
  String toString() => message.isEmpty ? failure.name : message;
}

/// Abstraksi klien Ethereum agar [ChainAnchorService] bisa diuji tanpa jaringan.
abstract interface class EthClient {
  Future<int> getChainId();

  Future<BigInt> getBalanceWei(String address);

  Future<String> sendDataTransaction(
    EthPrivateKey credentials,
    String utf8Payload,
    String to,
  );

  Future<String?> getTransactionInputUtf8(String txHash);

  Future<EthTxStatus> getReceiptStatus(String txHash);
}

/// Implementasi [EthClient] berbasis web3dart dan HTTP JSON-RPC.
///
/// Setiap panggilan punya batas waktu 15 detik. URL kosong tidak membuat
/// konstruktor gagal; panggilan pertama melempar
/// [AnchorFailure.notConfigured].
class Web3EthClient implements EthClient {
  Web3EthClient(
      {String rpcUrl = AppConfig.sepoliaRpcUrl, http.Client? httpClient})
      : _rpcUrl = rpcUrl,
        _http = httpClient ?? http.Client() {
    _web3 = Web3Client(_rpcUrl, _http);
  }

  static const chainId = AppConfig.sepoliaChainId;

  static const _timeout = Duration(seconds: 15);

  final String _rpcUrl;
  final http.Client _http;
  late final Web3Client _web3;

  void _ensureConfigured() {
    if (_rpcUrl.trim().isEmpty) {
      throw const AnchorException(
        AnchorFailure.notConfigured,
        'RPC belum dikonfigurasi',
      );
    }
  }

  Future<T> _withTimeout<T>(Future<T> Function() call) async {
    _ensureConfigured();
    try {
      return await call().timeout(_timeout);
    } on TimeoutException {
      throw const AnchorException(
        AnchorFailure.network,
        'Jaringan lambat. Coba lagi.',
      );
    }
  }

  @override
  Future<int> getChainId() async {
    final id = await _withTimeout(_web3.getChainId);
    return id.toInt();
  }

  @override
  Future<BigInt> getBalanceWei(String address) async {
    final balance = await _withTimeout(
      () => _web3.getBalance(EthereumAddress.fromHex(address)),
    );
    return balance.getInWei;
  }

  /// Bangun transaksi anchor: value nol, tujuan alamat sendiri, data payload.
  ///
  /// Dipisah supaya test bisa memeriksa bentuk transaksi tanpa jaringan.
  Transaction buildAnchorTransaction(
    EthereumAddress to,
    Uint8List data,
  ) =>
      Transaction(
        to: to,
        value: EtherAmount.zero(),
        data: data,
      );

  @override
  Future<String> sendDataTransaction(
    EthPrivateKey credentials,
    String utf8Payload,
    String to,
  ) async {
    final transaction = buildAnchorTransaction(
      EthereumAddress.fromHex(to),
      Uint8List.fromList(utf8.encode(utf8Payload)),
    );
    return _withTimeout(
      () => _web3.sendTransaction(
        credentials,
        transaction,
        chainId: chainId,
      ),
    );
  }

  @override
  Future<String?> getTransactionInputUtf8(String txHash) async {
    final information = await _withTimeout(
      () => _web3.getTransactionByHash(txHash),
    );
    if (information == null) return null;
    return utf8.decode(information.input, allowMalformed: true);
  }

  @override
  Future<EthTxStatus> getReceiptStatus(String txHash) async {
    final receipt = await _withTimeout(
      () => _web3.getTransactionReceipt(txHash),
    );
    if (receipt == null || receipt.status == null) return EthTxStatus.pending;
    return receipt.status! ? EthTxStatus.success : EthTxStatus.failed;
  }

  /// Tutup koneksi HTTP. Dipakai saat provider dibuang.
  void dispose() => _http.close();
}

/// Catatan anchor yang disimpan lokal.
class AnchorRecord {
  const AnchorRecord({
    required this.txHash,
    required this.headHash,
    required this.headIndex,
    required this.chainLength,
    required this.createdAtMs,
    required this.explorerUrl,
    required this.status,
  });

  final String txHash;
  final String headHash;
  final int headIndex;
  final int chainLength;
  final int createdAtMs;
  final String explorerUrl;
  final AnchorStatus status;

  AnchorRecord copyWith({AnchorStatus? status}) => AnchorRecord(
        txHash: txHash,
        headHash: headHash,
        headIndex: headIndex,
        chainLength: chainLength,
        createdAtMs: createdAtMs,
        explorerUrl: explorerUrl,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'txHash': txHash,
        'headHash': headHash,
        'headIndex': headIndex,
        'chainLength': chainLength,
        'createdAtMs': createdAtMs,
        'explorerUrl': explorerUrl,
        'status': status.name,
      };

  /// Parse toleran: field yang hilang atau salah tipe tidak menghilangkan
  /// seluruh riwayat anchor.
  factory AnchorRecord.fromJson(Map<String, dynamic> json) {
    final hash = (json['headHash'] as String?) ?? '';
    final txHash = (json['txHash'] as String?) ?? '';
    final storedUrl = (json['explorerUrl'] as String?) ?? '';
    return AnchorRecord(
      txHash: txHash,
      headHash: hash,
      headIndex: (json['headIndex'] as num?)?.toInt() ?? 0,
      chainLength: (json['chainLength'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      explorerUrl: storedUrl.isNotEmpty
          ? storedUrl
          : (txHash.isEmpty ? '' : AppConfig.explorerTxUrl(txHash)),
      status: json['status'] == AnchorStatus.confirmed.name
          ? AnchorStatus.confirmed
          : AnchorStatus.pending,
    );
  }
}

/// Hasil verifikasi anchor terhadap rantai lokal.
enum AnchorVerifyResult {
  verified,
  pending,
  mismatch,
  notFound,
  networkError,
  localChainDiverged,
}

/// Layanan publikasi head hash rantai paspor ke Sepolia dan verifikasinya.
///
/// Tidak ada UI dan tidak ada penyimpanan di sini: pemanggil yang menyimpan
/// [AnchorRecord] lewat `AnchorStore`. Semua kegagalan yang bisa diantisipasi
/// dilempar sebagai [AnchorException] dengan [AnchorFailure] yang stabil.
class ChainAnchorService {
  ChainAnchorService({
    required EthClient client,
    required WalletRepository wallet,
    String rpcUrl = AppConfig.sepoliaRpcUrl,
    Duration receiptTimeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
    Future<void> Function(Duration)? delay,
    Future<EthPrivateKey> Function()? credentials,
    Future<String> Function()? address,
  })  : _client = client,
        _rpcUrl = rpcUrl,
        _receiptTimeout = receiptTimeout,
        _pollInterval = pollInterval,
        _delay = delay ?? _systemDelay,
        _credentials = credentials ?? wallet.anchorCredentials,
        _address = address ?? wallet.anchorAddress;

  final EthClient _client;
  final Future<EthPrivateKey> Function() _credentials;
  final Future<String> Function() _address;
  final String _rpcUrl;
  final Duration _receiptTimeout;
  final Duration _pollInterval;
  final Future<void> Function(Duration) _delay;

  static Future<void> _systemDelay(Duration duration) =>
      Future<void>.delayed(duration);

  /// Publish `UFZ1:<headHash>` sebagai transaksi data ke Sepolia.
  ///
  /// Menolak rantai lokal tidak valid, RPC kosong, chain id selain Sepolia,
  /// dan saldo nol. Timeout receipt tidak melempar: record dikembalikan
  /// dengan status pending. Receipt gagal/revert menjadi typed failure.
  Future<AnchorRecord> anchor(List<Block> chain) async {
    if (!Blockchain.isValid(chain)) {
      throw const AnchorException(
        AnchorFailure.invalidChain,
        'Rantai paspor lokal tidak valid.',
      );
    }
    if (_rpcUrl.trim().isEmpty) {
      throw const AnchorException(
        AnchorFailure.notConfigured,
        'RPC belum dikonfigurasi',
      );
    }

    final chainId = await _guard(_client.getChainId);
    if (chainId != AppConfig.sepoliaChainId) {
      throw const AnchorException(
        AnchorFailure.wrongNetwork,
        'RPC bukan jaringan Sepolia.',
      );
    }

    final address = await _guard(_address);
    final balance = await _guard(() => _client.getBalanceWei(address));
    if (balance == BigInt.zero) {
      throw const AnchorException(
        AnchorFailure.insufficientFunds,
        'Saldo testnet nol. Isi faucet Sepolia terlebih dahulu.',
      );
    }

    final head = chain.last;
    final payload = 'UFZ1:${head.hash}';
    final credentials = await _guard(_credentials);
    final txHash = await _guard(
      () => _client.sendDataTransaction(credentials, payload, address),
    );

    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final record = AnchorRecord(
      txHash: txHash,
      headHash: head.hash,
      headIndex: head.index,
      chainLength: chain.length,
      createdAtMs: createdAtMs,
      explorerUrl: AppConfig.explorerTxUrl(txHash),
      status: AnchorStatus.pending,
    );

    return _pollReceipt(record);
  }

  /// Perbarui status record yang masih pending. Tidak pernah melempar.
  Future<AnchorRecord> refreshStatus(AnchorRecord record) async {
    if (record.status == AnchorStatus.confirmed) return record;
    try {
      final receipt = await _client.getReceiptStatus(record.txHash);
      if (receipt == EthTxStatus.success) {
        return record.copyWith(status: AnchorStatus.confirmed);
      }
    } catch (_) {
      // Status jaringan gagal: biarkan pending, pemanggil bisa coba lagi.
    }
    return record;
  }

  /// Verifikasi bahwa transaksi on-chain cocok dengan record dan rantai lokal.
  Future<AnchorVerifyResult> verify(
    AnchorRecord record,
    List<Block> localChain,
  ) async {
    if (record.status == AnchorStatus.pending) {
      return AnchorVerifyResult.pending;
    }

    final String? input;
    try {
      input = await _client.getTransactionInputUtf8(record.txHash);
    } catch (_) {
      return AnchorVerifyResult.networkError;
    }
    if (input == null) return AnchorVerifyResult.notFound;
    if (input != 'UFZ1:${record.headHash}') {
      return AnchorVerifyResult.mismatch;
    }

    Block? localHead;
    for (final block in localChain) {
      if (block.index == record.headIndex) {
        localHead = block;
        break;
      }
    }
    if (!Blockchain.isValid(localChain) ||
        localHead == null ||
        localHead.hash != record.headHash) {
      return AnchorVerifyResult.localChainDiverged;
    }
    return AnchorVerifyResult.verified;
  }

  Future<AnchorRecord> _pollReceipt(AnchorRecord record) async {
    final deadline = DateTime.now().add(_receiptTimeout);
    while (true) {
      final status = await _guard(
        () => _client.getReceiptStatus(record.txHash),
      );
      if (status == EthTxStatus.success) {
        return record.copyWith(status: AnchorStatus.confirmed);
      }
      if (status == EthTxStatus.failed) {
        throw const AnchorException(
          AnchorFailure.reverted,
          'Transaksi anchor gagal di jaringan.',
        );
      }
      if (!DateTime.now().isBefore(deadline)) return record;
      await _delay(_pollInterval);
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AnchorException {
      rethrow;
    } on TimeoutException {
      throw const AnchorException(
        AnchorFailure.network,
        'Jaringan lambat. Coba lagi.',
      );
    } on SocketException {
      throw const AnchorException(
        AnchorFailure.network,
        'Tidak ada koneksi ke jaringan.',
      );
    } on http.ClientException {
      throw const AnchorException(
        AnchorFailure.network,
        'Tidak ada koneksi ke jaringan.',
      );
    } catch (error) {
      final type = error.runtimeType.toString().toLowerCase();
      if (type.contains('socket') ||
          type.contains('timeout') ||
          type.contains('connection') ||
          type.contains('http')) {
        throw const AnchorException(
          AnchorFailure.network,
          'Tidak ada koneksi ke jaringan.',
        );
      }
      throw const AnchorException(
        AnchorFailure.rejected,
        'Permintaan anchor ditolak RPC.',
      );
    }
  }
}
