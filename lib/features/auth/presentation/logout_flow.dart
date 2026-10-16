import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../sync/providers/sync_provider.dart';
import 'login_screen.dart';

/// Nama koleksi yang dipakai di dialog, dalam Bahasa Indonesia.
const _collectionLabels = <String, String>{
  'away_day_expenses': 'Pengeluaran Away Day',
  'score_predictions': 'Prediksi skor',
  'passport_chain': 'Paspor Suporter',
};

String _label(String collection) => _collectionLabels[collection] ?? collection;

/// Keluar dari akun dengan perlindungan data yang belum tersinkron.
///
/// Sebelum menghapus sesi, kalau masih ada perubahan lokal yang belum dikirim
/// dan perangkat sedang online, sinkronisasi dicoba dulu (maks. 15 detik).
/// Kalau tetap ada sisa, pengguna diberi tahu agar tidak kehilangan data tanpa
/// sadar. Setelah dikonfirmasi, sesi dan data pengguna dihapus.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await _confirmLogout(context, ref);
  if (confirmed != true || !context.mounted) return;

  await ref.read(logoutProvider)();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

/// Kembalikan true bila pengguna benar-benar ingin keluar.
Future<bool?> _confirmLogout(BuildContext context, WidgetRef ref) async {
  var pending = await OfflineSyncDatabase.pendingCollections();
  final online = ref.read(onlineProvider).valueOrNull ?? false;

  if (pending.isNotEmpty && online) {
    try {
      await ref
          .read(syncProvider.notifier)
          .run()
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // Sinkronisasi lambat: lanjut tawarkan pilihan ke pengguna.
    } catch (_) {
      // Sinkronisasi gagal: biarkan sisa data ditampilkan di dialog.
    }
    pending = await OfflineSyncDatabase.pendingCollections();
  }

  if (!context.mounted) return null;
  if (pending.isEmpty) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text('Sesi akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  final daftar = pending.map((c) => '• ${_label(c)}').join('\n');
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Data belum dicadangkan'),
      content: Text(
        'Masih ada data yang belum terkirim ke server:\n\n$daftar\n\n'
        'Kalau keluar sekarang, data itu akan dihapus dari perangkat ini '
        'dan tidak bisa dipulihkan.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Keluar tetap'),
        ),
      ],
    ),
  );
}
