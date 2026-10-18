import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';

void main() {
  group('U4: data pengguna', () {
    test('daftar kunci mencakup data pengguna yang dibersihkan saat logout',
        () {
      const keys = AuthRepository.userDataKeys;
      expect(keys, contains('away_day_expenses'));
      expect(keys, contains('score_predictions'));
      expect(keys, contains('passport_chain'));
      expect(keys, isNot(contains('profile_photo_path')));
      expect(keys, isNot(contains('profile_display_name')));
      expect(keys, isNot(contains('away_day_budget_idr')));
      expect(keys, isNot(contains('favorite_team')));
      expect(keys, isNot(contains('pam_feedback')));
    });

    test('kunci prefs perangkat tidak ikut dihapus', () {
      const keys = AuthRepository.userDataKeys;
      expect(keys.contains('theme_mode'), isFalse);
      expect(keys.contains('permission_rationale'), isFalse);
    });

    test('prefix cache Pundit ikut dibersihkan', () {
      expect(AuthRepository.userKeyPrefixes, contains('pundit_'));
    });

    test('logout menghapus private key wallet', () async {
      FlutterSecureStorage.setMockInitialValues(
          {'wallet_private_key': 'abcdef'});
      final repo =
          AuthRepository(const FlutterSecureStorage(), LocalAuthentication());
      await repo.logout();
      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'wallet_private_key'), isNull);
    });
  });
}
