import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auto_lock_policy.dart';
import '../providers/auth_provider.dart';
import 'lock_screen.dart';

/// true selagi aksi yang membuka dialog sistem (kamera, galeri, prompt
/// biometrik) sedang berjalan. Selama true, auto-lock tidak dijalankan supaya
/// dialog itu tidak dianggap pengguna meninggalkan aplikasi.
final appLockSuspendedProvider = StateProvider<bool>((ref) => false);

/// Jalankan [action] tanpa memicu kunci otomatis saat aplikasi kembali aktif.
///
/// Dipakai sebelum membuka kamera/galeri atau prompt biometrik, yang membuat
/// aplikasi masuk ke state `paused` walau pengguna tidak benar-benar
/// meninggalkannya.
Future<T> withoutAutoLock<T>(WidgetRef ref, Future<T> Function() action) async {
  final suspended = ref.read(appLockSuspendedProvider.notifier);
  suspended.state = true;
  try {
    return await action();
  } finally {
    suspended.state = false;
  }
}

/// Membungkus Dashboard: begitu aplikasi kembali dari latar belakang setelah
/// [AutoLockPolicy.timeout], dorong [LockScreen] di atas Dashboard.
///
/// LockScreen didorong dengan `popOnSuccess: true` supaya setelah dibuka
/// pengguna kembali ke tab yang sama, bukan dibangun ulang dari awal.
class AutoLockObserver extends ConsumerStatefulWidget {
  const AutoLockObserver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AutoLockObserver> createState() => _AutoLockObserverState();
}

class _AutoLockObserverState extends ConsumerState<AutoLockObserver>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;
  bool _locking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _maybeLock();
    }
  }

  void _maybeLock() {
    final pausedAt = _pausedAt;
    // Selalu bersihkan penanda jeda supaya jeda berikutnya dihitung ulang.
    _pausedAt = null;
    if (pausedAt == null || _locking) return;
    // Sedang membuka kamera/galeri/prompt biometrik: jangan kunci.
    if (ref.read(appLockSuspendedProvider)) return;
    final shouldLock = AutoLockPolicy.shouldLock(
      pausedAt: pausedAt,
      now: DateTime.now(),
      biometricEnabled: ref.read(biometricEnabledProvider),
    );
    if (!shouldLock) return;

    _locking = true;
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute<bool>(
          builder: (_) => const LockScreen(popOnSuccess: true),
        ))
        .whenComplete(() => _locking = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
