import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/connectivity_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../sync/providers/sync_provider.dart';
import '../data/auth_repository.dart';
import 'login_screen.dart';

/// Nama koleksi yang dipakai di dialog, dalam Bahasa Indonesia.
const _collectionLabels = <String, String>{
  'away_day_expenses': 'Pengeluaran Away Day',
  'score_predictions': 'Prediksi skor',
  'passport_chain': 'Paspor Suporter',
};

/// Baris ringkas untuk semua penghapusan yang belum terkirim.
const _deletionsLabel = 'Penghapusan belum terkirim';

/// Baris ringkas untuk nama/favorit/anggaran yang belum naik ke server.
const _prefsLabel = 'Nama, klub favorit, dan anggaran';

String _label(String collection) => _collectionLabels[collection] ?? collection;

/// Aksi sinkronisasi yang dipakai dialog keluar.
///
/// Memisahkan efek samping (sync + prefs retry) dari logika dialog supaya bisa
/// diganti di test, tanpa mengubah perilaku produksi. Mengembalikan pesan error
/// sinkronisasi bila ada, atau null saat berhasil.
final logoutSyncAttemptProvider = Provider<Future<String?> Function()>((ref) {
  return () async {
    await ref.read(authRepositoryProvider).retryPendingPrefs();
    await ref.read(syncProvider.notifier).run();
    return ref.read(syncProvider).error;
  };
});

/// Semua data yang belum naik ke server, sebagai baris siap tampil di dialog.
Future<List<String>> _pendingRows(WidgetRef ref) async {
  final rows = <String>[
    for (final c in await OfflineSyncDatabase.pendingCollections()) _label(c),
  ];
  if ((await OfflineSyncDatabase.pendingDeletions()).isNotEmpty) {
    rows.add(_deletionsLabel);
  }
  final repo = ref.read(authRepositoryProvider);
  final userId = repo.currentUserId;
  if (userId != null &&
      repo.identityStore.get(AuthRepository.prefsPendingKey(userId)) ==
          'true') {
    rows.add(_prefsLabel);
  }
  return rows;
}

/// Coba sinkron lalu hitung ulang sisa data yang belum terkirim.
Future<({List<String> rows, String? cause})> _syncAttempt(WidgetRef ref) async {
  String? cause;
  try {
    cause = await ref
        .read(logoutSyncAttemptProvider)()
        .timeout(const Duration(seconds: 15));
  } on TimeoutException {
    // Sinkronisasi lambat: lanjut tawarkan pilihan ke pengguna.
  } catch (_) {
    // Sinkronisasi gagal: sisa data tetap ditampilkan di dialog.
  }
  cause ??= ref.read(syncProvider).error;
  return (rows: await _pendingRows(ref), cause: cause);
}

// STRUKTUR UI — confirmAndLogout (alur keluar)
// Ukuran: bukan widget; satu dialog AlertDialog konfirmasi.
// [1] Dialog keluar    — muncul bila tidak ada data lokal yang belum
//                        terkirim; tombol Batal dan Keluar
// [2] Dialog data belum dicadangkan — muncul bila masih ada sisa data:
//                        daftar baris, tombol Batal, Coba sinkron lagi
//                        (maksimal satu percobaan), dan Keluar tetap
// [3] Isi peringatan  — teks daftar data per baris, konsekuensi keluar, nota
//                        perangkat offline, dan penyebab kegagalan sinkron
// Tabel/kolom: tanpa tabel; daftar data ditulis satu baris per koleksi.
// Sumber data: syncProvider, onlineProvider, authRepositoryProvider,
//              logoutProvider.
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
  final online = ref.read(onlineProvider).valueOrNull ?? false;

  List<String> rows;
  String? cause;
  if (online) {
    final attempt = await _syncAttempt(ref);
    rows = attempt.rows;
    cause = attempt.cause;
  } else {
    rows = await _pendingRows(ref);
  }

  // Satu coba-ulang manual per sesi dialog; setelah itu tombolnya hilang,
  // jadi tidak ada loop.
  var retried = false;
  while (true) {
    if (!context.mounted) return null;
    if (rows.isEmpty) {
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

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Data belum dicadangkan'),
        content: Text(_warningText(rows, online: online, cause: cause)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'batal'),
            child: const Text('Batal'),
          ),
          if (online && !retried)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Coba sinkron lagi'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, 'keluar'),
            child: const Text('Keluar tetap'),
          ),
        ],
      ),
    );

    if (action == 'retry') {
      retried = true;
      final attempt = await _syncAttempt(ref);
      rows = attempt.rows;
      cause = attempt.cause;
      continue;
    }
    return action == 'keluar';
  }
}

/// Isi dialog peringatan: daftar data, konsekuensi, plus catatan offline/error.
String _warningText(
  List<String> rows, {
  required bool online,
  String? cause,
}) {
  final daftar = rows.map((r) => '• $r').join('\n');
  final buffer = StringBuffer(
    'Masih ada data yang belum terkirim ke server:\n\n$daftar\n\n'
    'Kalau keluar sekarang, data itu akan dihapus dari perangkat ini '
    'dan tidak bisa dipulihkan.',
  );
  if (!online) buffer.write('\n\nPerangkat sedang offline.');
  if (cause != null && cause.isNotEmpty) {
    buffer.write('\n\nPenyebab: $cause');
  }
  return buffer.toString();
}
