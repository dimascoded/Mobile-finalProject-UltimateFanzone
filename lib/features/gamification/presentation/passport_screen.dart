import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/ui/app_images.dart';
import '../../../core/ui/pill_badge.dart';
import '../../../core/ui/scrim_image.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/settings_section.dart';
import '../../../core/utils/app_config.dart';
import '../../../core/utils/external_launcher.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/presentation/team_picker_screen.dart';
import '../../football/providers/football_providers.dart';
import '../data/blockchain.dart';
import '../data/chain_anchor_service.dart' hide AnchorStatus;
import '../providers/anchor_coordinator.dart' show AnchorStatus;
import '../providers/card_collection_provider.dart';
import '../providers/gamification_providers.dart';
import 'card_collection_screen.dart';

// STRUKTUR UI — PassportScreen
// Ukuran: Scaffold + AppBar, body ListView satu kolom tanpa batas lebar;
// header ScrimImage setinggi 190 * textScale
// [1] Empty state — kolom "Pilih tim favorit dulu" plus tombol menuju TeamPickerScreen
// [2] Header klub — ScrimImage: crest, nama klub, stadion dan kota, PillBadge jarak ke stadion
// [3] Kartu aksi cap — info radius cap, tombol "Cap stamp", switch mode demo
// [4] Status riwayat — SettingsTile validitas rantai catatan
// [5] Kartu Koleksi Kartu — ListTile jumlah kartu dan jumlah klub terkumpul
// [6] Daftar stamp stadion — SectionHeader lalu kartu kosong atau AppCard per catatan stamp
// Tabel/kolom: tanpa tabel; daftar stamp satu kolom (satu ListTile per catatan)
// Sumber data: favoriteClubProvider, clubCrestProvider, stampsProvider, chainValidProvider,
// demoModeProvider, stampProvider, stampDistanceProvider, cardCollectionProvider, ownedClubsProvider

class PassportScreen extends ConsumerStatefulWidget {
  const PassportScreen({super.key});

  @override
  ConsumerState<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends ConsumerState<PassportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(anchorCoordinatorProvider.notifier).ensureAnchored(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    ref.listen(stampProvider, (previous, next) {
      next.whenOrNull(
        data: (message) {
          if (message != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
        error: (error, _) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error.toString().replaceFirst('Exception: ', '')),
              ),
            );
          }
        },
      );
    });
    final club = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final stamps = ref.watch(stampsProvider);
    final valid = ref.watch(chainValidProvider);
    final demoMode = ref.watch(demoModeProvider);
    final busy = ref.watch(stampProvider).isLoading;
    final distance = ref.watch(stampDistanceProvider);
    final anchorWallet = ref.watch(anchorAddressProvider);
    final anchorStatus = ref.watch(anchorStatusProvider);
    final address = anchorWallet.valueOrNull;
    if (club == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paspor Suporter')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pilih tim favorit dulu'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TeamPickerScreen(),
                  ),
                ),
                child: const Text('Pilih tim'),
              ),
            ],
          ),
        ),
      );
    }

    final textScaler =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final headerHeight = 190.0 * textScaler;

    return Scaffold(
      appBar: AppBar(title: const Text('Paspor Suporter')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ScrimImage(
            assetPath: AppImages.headerLaga,
            height: headerHeight,
            scrim: 0.75,
            showPitchPattern: true,
            borderRadius: AppRadius.xl,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClubCrest(
                          crestUrl: crests[club.tla.toUpperCase()],
                          tla: club.tla,
                          color: club.colorValue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          club.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${club.stadium} • ${club.city}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PillBadge(
                    label: distance.when(
                      loading: () => 'Mengukur jarak ke stadion\u2026',
                      data: (m) {
                        if (m == null) {
                          return 'Jarak tidak diukur '
                              '(GPS mati atau izin belum diberikan).';
                        }
                        return 'Anda $m m dari ${club.stadium}.'
                            '${m <= stampRadiusMeters.round() ? ' Dalam jangkauan!' : ' Terlalu jauh untuk cap GPS.'}';
                      },
                      error: (e, _) =>
                          'Gagal mengukur jarak: ${e.toString().replaceFirst('Exception: ', '')}',
                    ),
                    tone: distance.when(
                      loading: () => PillTone.neutral,
                      data: (m) {
                        if (m == null || m > stampRadiusMeters.round()) {
                          return PillTone.neutral;
                        }
                        return PillTone.accent;
                      },
                      error: (_, __) => PillTone.neutral,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        demoMode
                            ? 'Mode demo aktif, GPS dilewati.'
                            : 'Cap tersedia dalam radius '
                                '${stampRadiusMeters.round()} m dari stadion.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (!demoMode)
                      IconButton(
                        tooltip: 'Perbarui jarak',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.invalidate(stampDistanceProvider),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildRegistrationStatus(
                  context,
                  stamps: stamps,
                  anchorStatus: anchorStatus,
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!demoMode) {
                              final allowed = await confirmPermission(
                                context,
                                ref,
                                permissionKey: 'location',
                                title: 'Izin lokasi untuk cap stadion',
                                message:
                                    'Lokasi digunakan untuk memeriksa jarak Anda dari stadion ${club.stadium}.',
                              );
                              if (!allowed || !context.mounted) return;
                            }
                            await ref.read(stampProvider.notifier).stamp(club);
                          },
                    child: busy
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: AppSpacing.sm),
                              Text('Mencetak\u2026'),
                            ],
                          )
                        : const Text('Cap stamp'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: address == null || address.trim().isEmpty
                        ? null
                        : () => _openExplorerAddress(context, address),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Cek di Sepolia Etherscan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode demo'),
                  subtitle: Text(
                    'Melewati pemeriksaan GPS',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: demoMode,
                  onChanged: (enabled) {
                    ref.read(demoModeProvider.notifier).state = enabled;
                    if (enabled) ref.invalidate(stampDistanceProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsTile(
            icon: Icon(valid ? Icons.verified : Icons.error),
            title: valid ? 'Riwayat aman' : 'Riwayat tidak cocok',
            subtitle: valid
                ? 'Semua pencapaianmu tercatat dan belum pernah diubah.'
                : 'Ada catatan yang tidak sesuai. Coba cadangkan ulang.',
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CardCollectionScreen(),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.style_outlined),
              title: Text(
                  'Koleksi Kartu (${ref.watch(cardCollectionProvider).length})'),
              subtitle: Text(
                  '${ref.watch(ownedClubsProvider).length} klub terkumpul'),
              trailing: const Icon(Icons.chevron_right),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: 'Stamp stadion ${club.name}'),
          const SizedBox(height: AppSpacing.md),
          if (stamps.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Belum ada stamp. Buka GPS lalu cap stadion favoritmu.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...stamps.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.approval,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      '${b.data['stadium']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Catatan #${b.index} • ${b.data['gps_verified'] == true ? 'GPS terverifikasi' : 'mode demo'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _StampProofChip(block: b),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegistrationStatus(
    BuildContext context, {
    required List<Block> stamps,
    required AnchorStatus anchorStatus,
  }) {
    if (stamps.isEmpty) return const SizedBox.shrink();

    final allConfirmed = stamps.every((block) {
      final proof = ref.read(stampProofProvider(block));
      return proof.kind == StampProofKind.confirmed;
    });

    if (allConfirmed) {
      final colorScheme = Theme.of(context).colorScheme;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Terdaftar di blockchain',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                ),
          ),
        ],
      );
    }

    final hasPendingProof = stamps.any((block) {
      final proof = ref.read(stampProofProvider(block));
      return proof.kind == StampProofKind.pending;
    });
    final isSending = anchorStatus == AnchorStatus.sending;

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Belum terdaftar',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isSending || hasPendingProof) ...[
              const SizedBox(width: AppSpacing.xs),
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (anchorStatus != AnchorStatus.sending)
          OutlinedButton.icon(
            onPressed: () {
              unawaited(
                ref
                    .read(anchorCoordinatorProvider.notifier)
                    .ensureAnchored(force: true),
              );
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Coba lagi'),
          ),
        if (kDebugMode)
          Builder(
            builder: (context) {
              String? reason;
              switch (anchorStatus) {
                case AnchorStatus.waitingFunds:
                  reason = 'Saldo dompet jangkar kosong';
                  break;
                case AnchorStatus.offline:
                  reason = 'Tidak ada jaringan';
                  break;
                case AnchorStatus.notConfigured:
                  reason = 'RPC Sepolia belum dikonfigurasi';
                  break;
                case AnchorStatus.failed:
                  reason = 'Gagal menjangkarkan';
                  break;
                case AnchorStatus.idle:
                case AnchorStatus.sending:
                  break;
              }
              if (reason == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _openExplorerAddress(
    BuildContext context,
    String address,
  ) =>
      _launchExternal(
        context,
        ref,
        Uri.parse(AppConfig.explorerAddressUrl(address)),
      );

}

class _StampProofChip extends ConsumerWidget {
  const _StampProofChip({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proof = ref.watch(stampProofProvider(block));
    final label = switch (proof.kind) {
      StampProofKind.confirmed => 'Terbukti di Sepolia',
      StampProofKind.pending => 'Menunggu konfirmasi',
      StampProofKind.none => 'Belum dijangkarkan',
    };
    final tone = switch (proof.kind) {
      StampProofKind.confirmed => PillTone.success,
      StampProofKind.pending => PillTone.accent,
      StampProofKind.none => PillTone.neutral,
    };
    final chip = PillBadge(label: label, tone: tone);
    final record = proof.record;
    if (record == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: () => _showProofSheet(context, record),
      child: chip,
    );
  }
}

class _ProofSheet extends ConsumerStatefulWidget {
  const _ProofSheet({required this.record});

  final AnchorRecord record;

  @override
  ConsumerState<_ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends ConsumerState<_ProofSheet> {
  bool _verifying = false;
  String? _result;

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _result = null;
    });
    try {
      final result = await ref
          .read(chainAnchorServiceProvider)
          .verify(widget.record, ref.read(chainProvider));
      if (!mounted) return;
      setState(() => _result = _verifyResultText(result));
    } catch (_) {
      if (!mounted) return;
      setState(() => _result = 'Tidak bisa memeriksa, coba lagi nanti');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _copyHash() async {
    await Clipboard.setData(ClipboardData(text: widget.record.txHash));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hash transaksi disalin')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bukti Sepolia',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortHash(widget.record.txHash),
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Salin hash transaksi',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copyHash,
                  icon: const Icon(Icons.copy, size: 18),
                ),
              ],
            ),
            Text(
              'Catatan #${widget.record.headIndex}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _launchExternal(
                  context,
                  ref,
                  Uri.parse(
                    AppConfig.explorerTxUrl(widget.record.txHash),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Buka di Etherscan'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verifying ? null : _verify,
                icon: _verifying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Verifikasi on-chain'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _result!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _showProofSheet(BuildContext context, AnchorRecord record) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProofSheet(record: record),
  );
}

Future<void> _launchExternal(
  BuildContext context,
  WidgetRef ref,
  Uri uri, {
  String errorMessage = 'Tidak bisa membuka Etherscan',
}) async {
  try {
    final opened = await ref.read(externalLauncherProvider)(uri);
    if (!opened && context.mounted) {
      _showLaunchError(context, errorMessage);
    }
  } catch (_) {
    if (context.mounted) _showLaunchError(context, errorMessage);
  }
}

void _showLaunchError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

String _shortHash(String hash) {
  if (hash.length <= 20) return hash;
  return '${hash.substring(0, 10)}\u2026${hash.substring(hash.length - 8)}';
}

String _verifyResultText(AnchorVerifyResult result) {
  switch (result) {
    case AnchorVerifyResult.verified:
      return 'Cocok dengan rantai di perangkat';
    case AnchorVerifyResult.mismatch:
    case AnchorVerifyResult.localChainDiverged:
      return 'Tidak cocok';
    case AnchorVerifyResult.networkError:
      return 'Tidak bisa memeriksa, coba lagi nanti';
    case AnchorVerifyResult.notFound:
    case AnchorVerifyResult.pending:
      return 'Transaksi belum ditemukan di Sepolia';
  }
}
