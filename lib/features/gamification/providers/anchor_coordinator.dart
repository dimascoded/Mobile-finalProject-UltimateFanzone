import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_provider.dart';
import '../../../core/utils/app_config.dart';
import '../../auth/data/auth_repository.dart';
import '../data/anchor_store.dart';
import '../data/blockchain.dart';
import '../data/chain_anchor_service.dart' as anchor;
import 'gamification_providers.dart';

/// Status koordinasi anchor untuk ditampilkan di Passport.
enum AnchorStatus {
  idle,
  sending,
  waitingFunds,
  offline,
  notConfigured,
  failed,
}

/// Mengoordinasikan pengiriman head rantai paspor ke Sepolia.
///
/// Hanya membaca rantai dan riwayat anchor; tidak pernah menulis rantai,
/// memanggil [ChainNotifier.mint]/`replaceAll`, atau mencetak kartu.
class AnchorCoordinator extends StateNotifier<AnchorStatus> {
  AnchorCoordinator(
    Ref? ref, {
    bool? rpcConfigured,
    DateTime Function()? now,
    List<Block> Function()? readChain,
    ChainAnchorServiceFactory? service,
    AnchorStore Function()? store,
    String? Function()? currentUserId,
    bool listenConnectivity = true,
  })  : _ref = ref,
        _rpcConfigured = rpcConfigured ?? AppConfig.sepoliaRpcUrl.isNotEmpty,
        _now = now ?? DateTime.now,
        _readChain = readChain ?? (() => ref!.read(chainProvider)),
        _readService =
            service ?? (() => ref!.read(chainAnchorServiceProvider)),
        _readStore = store ?? (() => ref!.read(anchorStoreProvider)),
        _userId = currentUserId ??
            (() => ref!.read(authRepositoryProvider).currentUserId),
        super(AnchorStatus.idle) {
    _listenForConnectivity(listenConnectivity);
  }

  static const retryDelay = Duration(minutes: 5);

  final Ref? _ref;
  final bool _rpcConfigured;
  final DateTime Function() _now;
  final List<Block> Function() _readChain;
  final ChainAnchorServiceFactory _readService;
  final AnchorStore Function() _readStore;
  final String? Function() _userId;

  bool _sending = false;
  bool _dirty = false;
  DateTime? _lastFailureAt;

  void _listenForConnectivity(bool enabled) {
    final ref = _ref;
    if (!enabled || ref == null) return;
    ref.listen<AsyncValue<bool>>(onlineProvider, (previous, next) {
      final wasOffline = previous?.valueOrNull == false;
      final isOnline = next.valueOrNull == true;
      if (wasOffline && isOnline) {
        unawaited(ensureAnchored());
      }
    });
  }

  /// Pastikan semua stamp sudah tercakup anchor.
  ///
  /// Pemeriksaan konfigurasi adalah hal pertama yang dilakukan, sebelum
  /// menyentuh secure storage, Hive, dompet, atau penyimpanan anchor. Metode
  /// ini tidak pernah melempar ke pemanggil.
  Future<void> ensureAnchored({bool force = false}) async {
    if (!_rpcConfigured) {
      _setStatus(AnchorStatus.notConfigured);
      return;
    }
    if (_sending) {
      _dirty = true;
      return;
    }
    if (!force &&
        _lastFailureAt != null &&
        _now().difference(_lastFailureAt!) < retryDelay) {
      return;
    }

    String? userId;
    try {
      userId = _userId();
      if (userId == null || userId.trim().isEmpty) return;

      final chain = List<Block>.of(_readChain());
      final stamps = chain.where((b) => b.type == 'stamp').toList();
      if (stamps.isEmpty) return;

      final store = _readStore();
      final records = store.load();
      final highestStampIndex = stamps.last.index;
      final highestHead = records.fold<int>(
        0,
        (highest, record) =>
            record.headIndex > highest ? record.headIndex : highest,
      );

      if (stamps.every((stamp) => stamp.index <= highestHead)) {
        await _refreshCoveringPending(
          store,
          records,
          highestStampIndex,
          userId,
        );
        return;
      }

      await _send(chain, userId, store);
    } catch (error) {
      if (userId != null) _markFailure(error, userId);
    }
  }

  Future<void> _send(
    List<Block> chain,
    String userId,
    AnchorStore store,
  ) async {
    _dirty = false;
    _sending = true;
    _setStatus(AnchorStatus.sending);
    try {
      final record = await _readService().anchor(chain);
      if (!mounted || _userId() != userId) return;
      await store.add(record);
      if (!mounted || _userId() != userId) return;
      _ref?.invalidate(anchorsProvider);
      _ref?.invalidate(walletBalanceProvider);
      _lastFailureAt = null;
      _setStatus(AnchorStatus.idle);
    } catch (error) {
      _markFailure(error, userId);
    } finally {
      _sending = false;
      final shouldRetry = _dirty;
      _dirty = false;
      if (shouldRetry &&
          mounted &&
          _userId() == userId &&
          _hasUnanchored(userId)) {
        unawaited(ensureAnchored());
      }
    }
  }

  Future<void> _refreshCoveringPending(
    AnchorStore store,
    List<anchor.AnchorRecord> records,
    int highestStampIndex,
    String userId,
  ) async {
    anchor.AnchorRecord? pending;
    for (final record in records) {
      if (record.status == anchor.AnchorStatus.pending &&
          record.headIndex >= highestStampIndex) {
        pending = record;
        break;
      }
    }
    if (pending == null) return;

    try {
      final refreshed = await _readService().refreshStatus(pending);
      if (!mounted || _userId() != userId) return;
      if (refreshed.status != pending.status) {
        await store.update(refreshed);
        if (!mounted || _userId() != userId) return;
        _ref?.invalidate(anchorsProvider);
      }
    } catch (_) {
      // Status tetap pending; percobaan berikutnya boleh menyegarkan lagi.
    }
  }

  bool _hasUnanchored(String userId) {
    try {
      if (_userId() != userId) return false;
      final stamps =
          _readChain().where((block) => block.type == 'stamp').toList();
      if (stamps.isEmpty) return false;
      final highestHead = _readStore().load().fold<int>(
            0,
            (highest, record) =>
                record.headIndex > highest ? record.headIndex : highest,
          );
      return stamps.any((stamp) => stamp.index > highestHead);
    } catch (_) {
      return false;
    }
  }

  void _markFailure(Object error, String userId) {
    if (!mounted || _userId() != userId) return;
    _lastFailureAt = _now();
    _setStatus(_statusFor(error));
  }

  AnchorStatus _statusFor(Object error) {
    if (error is anchor.AnchorException) {
      switch (error.failure) {
        case anchor.AnchorFailure.insufficientFunds:
          return AnchorStatus.waitingFunds;
        case anchor.AnchorFailure.network:
          return AnchorStatus.offline;
        case anchor.AnchorFailure.notConfigured:
          return AnchorStatus.notConfigured;
        default:
          return AnchorStatus.failed;
      }
    }
    return AnchorStatus.failed;
  }

  void _setStatus(AnchorStatus next) {
    if (!mounted) return;
    if (state != next) state = next;
  }
}

typedef ChainAnchorServiceFactory = anchor.ChainAnchorService Function();
