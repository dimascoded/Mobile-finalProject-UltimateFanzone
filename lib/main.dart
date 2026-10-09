import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/database/hive_service.dart';
import 'core/database/offline_sync_database.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/app_config.dart';
import 'features/auth/presentation/lock_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/football/providers/kickoff_reminder_provider.dart';
import 'features/football/providers/result_notification_provider.dart';
import 'features/sos_emergency/data/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  await OfflineSyncDatabase.initialize();
  await OfflineSyncDatabase.importHiveData();
  if (AppConfig.hasPartialSupabaseConfig) {
    throw StateError(
      'SUPABASE_URL dan SUPABASE_ANON_KEY harus diisi bersama-sama.',
    );
  }
  if (AppConfig.supabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: _SecureSupabaseLocalStorage(),
      ),
    );
  }
  await NotificationService.init();
  runApp(const ProviderScope(child: MyApp()));
}

class _SecureSupabaseLocalStorage extends LocalStorage {
  const _SecureSupabaseLocalStorage();

  static const _sessionKey = 'supabase_auth_session';
  static const _storage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.read(key: _sessionKey) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Pengingat kickoff dan notifikasi hasil akhir, begitu cache pertandingan termuat.
    ref.watch(kickoffReminderSyncProvider);
    ref.watch(resultNotifierSyncProvider);
    ref.watch(pruneNotifiedProvider);
    return MaterialApp(
      title: 'Smart Football Fan',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      // Sesi valid -> LockScreen (biometrik); tidak ada/kedaluwarsa -> Login.
      home: session.when(
        data: (valid) => valid ? const LockScreen() : const LoginScreen(),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) =>
            Scaffold(body: Center(child: Text('Gagal memuat sesi: $e'))),
      ),
    );
  }
}
