import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ultimate_fanzone/features/auth/data/auth_repository.dart';
import 'package:ultimate_fanzone/features/auth/data/identity_store.dart';
import 'package:ultimate_fanzone/features/auth/providers/auth_provider.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/dashboard/providers/dashboard_provider.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';

class _MemoryIdentityStore implements IdentityStore {
  final values = <String, String>{};

  @override
  String? get(String key) => values[key];

  @override
  Future<void> put(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(
    this.store, {
    Map<String, dynamic>? metadata,
    Future<void> Function(Map<String, dynamic>)? updateMetadata,
  }) : super(const FlutterSecureStorage(), LocalAuthentication(),
            identityStore: store,
            updateUserMetadata: updateMetadata,
            readUserMetadata: () => metadata ?? const {});

  final _MemoryIdentityStore store;
  final emails = <String, String>{};
  String? activeUserId;
  int emailReads = 0;

  @override
  String? get currentUserId => activeUserId;

  @override
  Future<void> login(String email, String password) async {
    activeUserId = email.startsWith('alice') ? 'account-a' : 'account-b';
    emails[activeUserId!] = email;
  }

  @override
  Future<void> register(String email, String password, String confirm) async {
    activeUserId = 'registered-account';
    emails[activeUserId!] = email;
  }

  @override
  Future<void> logout() async {
    activeUserId = null;
  }

  @override
  Future<bool> hasSession() async => activeUserId != null;

  @override
  Future<String?> userEmail() async {
    emailReads++;
    return activeUserId == null ? null : emails[activeUserId];
  }

  @override
  Future<bool> canUseBiometric() async => false;
}

class _BiometricEnabledNotifier extends BiometricPreferenceNotifier {
  _BiometricEnabledNotifier() : super(initialState: true);
}

const _fakePhotoPath = 'fake://profile-photo.jpg';

ProviderContainer _container(_FakeAuthRepository repo) => ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith((ref) => AuthNotifier(
              repo,
              ref,
              clearData: () async {},
              clearOfflineSync: () async {},
            )),
        biometricEnabledProvider
            .overrideWith((ref) => _BiometricEnabledNotifier()),
        profilePhotoFileExistsProvider
            .overrideWithValue((path) => path.startsWith('fake://')),
      ],
    );

Future<void> _loadPhoto(ProviderContainer container) async {
  await container.read(profilePhotoProvider.notifier).reload();
}

void main() {
  group('identity provider lifecycle', () {
    test('same account reloads email, name, and photo after logout', () async {
      final store = _MemoryIdentityStore();
      final repo = _FakeAuthRepository(store);
      store.values.addAll({
        AuthRepository.displayNameKey('account-a'): 'Budi',
        AuthRepository.profilePhotoKey('account-a'): _fakePhotoPath,
        'favorite_team_account-a': 'arsenal',
        'away_day_budget_idr_account-a': '500000',
      });
      final container = _container(repo);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');
      final originalEmail = await container.read(userEmailProvider.future);
      final originalName =
          await container.read(effectiveDisplayNameProvider.future);
      await _loadPhoto(container);
      final originalPhoto = container.read(profilePhotoProvider);
      expect(container.read(favoriteKeyProvider), 'arsenal');
      expect(container.read(awayDayBudgetProvider), 500000);

      await container.read(authProvider.notifier).logout();
      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');

      expect(await container.read(userEmailProvider.future), originalEmail);
      expect(await container.read(effectiveDisplayNameProvider.future),
          originalName);
      await _loadPhoto(container);
      expect(container.read(profilePhotoProvider), originalPhoto);
      expect(container.read(awayDayBudgetProvider), 500000);
      expect(originalEmail, 'alice@mail.com');
      expect(originalName, 'Budi');
      expect(originalPhoto, _fakePhotoPath);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a different account sees no prior name, photo, or favorite',
        () async {
      final store = _MemoryIdentityStore();
      final repo = _FakeAuthRepository(store);
      store.values.addAll({
        AuthRepository.displayNameKey('account-a'): 'Budi',
        AuthRepository.profilePhotoKey('account-a'): _fakePhotoPath,
        'favorite_team_account-a': 'arsenal',
        'away_day_budget_idr_account-a': '500000',
      });
      final container = _container(repo);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');
      await _loadPhoto(container);
      expect(container.read(displayNameProvider), 'Budi');
      expect(container.read(profilePhotoProvider), _fakePhotoPath);
      expect(container.read(favoriteKeyProvider), 'arsenal');
      expect(container.read(awayDayBudgetProvider), 500000);

      await container.read(authProvider.notifier).logout();
      await container.read(authProvider.notifier).login('bob@mail.com', 'pw');
      await _loadPhoto(container);

      expect(container.read(displayNameProvider), isNull);
      expect(await container.read(effectiveDisplayNameProvider.future), 'bob');
      expect(container.read(profilePhotoProvider), isNull);
      expect(container.read(favoriteKeyProvider), isNull);
      expect(container.read(awayDayBudgetProvider), 0);
      expect(store.get(AuthRepository.displayNameKey('account-a')), 'Budi');
      expect(store.get(AuthRepository.profilePhotoKey('account-a')),
          _fakePhotoPath);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('cloud preferences load and cache when scoped values are absent', () {
      final store = _MemoryIdentityStore();
      final repo = _FakeAuthRepository(
        store,
        metadata: {
          'favorite_team': 'arsenal',
          'away_day_budget_idr': 500000,
        },
      )..activeUserId = 'account-a';
      final container = _container(repo);
      addTearDown(container.dispose);

      expect(container.read(favoriteKeyProvider), 'arsenal');
      expect(container.read(awayDayBudgetProvider), 500000);
      expect(store.get(AuthRepository.favoriteTeamKey('account-a')), 'arsenal');
      expect(
        store.get(AuthRepository.awayDayBudgetKey('account-a')),
        '500000',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('legacy profile keys migrate to the current account', () async {
      final store = _MemoryIdentityStore()
        ..values.addAll({
          'profile_display_name': 'Budi',
          'profile_photo_path': _fakePhotoPath,
          'favorite_team': 'arsenal',
          'away_day_budget_idr': '500000',
        });
      final repo = _FakeAuthRepository(store)..activeUserId = 'account-a';
      final container = _container(repo);
      addTearDown(container.dispose);

      expect(container.read(displayNameProvider), 'Budi');
      await _loadPhoto(container);
      expect(container.read(profilePhotoProvider), _fakePhotoPath);
      expect(container.read(favoriteKeyProvider), 'arsenal');
      expect(container.read(awayDayBudgetProvider), 500000);
      await Future<void>.delayed(Duration.zero);

      expect(store.get(AuthRepository.displayNameKey('account-a')), 'Budi');
      expect(store.get(AuthRepository.profilePhotoKey('account-a')),
          _fakePhotoPath);
      expect(store.get(AuthRepository.favoriteTeamKey('account-a')), 'arsenal');
      expect(store.get(AuthRepository.awayDayBudgetKey('account-a')), '500000');
      expect(store.get('profile_display_name'), isNull);
      expect(store.get('profile_photo_path'), isNull);
      expect(store.get('favorite_team'), isNull);
      expect(store.get('away_day_budget_idr'), isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('budget writes scoped Hive before cloud metadata', () async {
      final store = _MemoryIdentityStore();
      final metadata = <String, dynamic>{'display_name': 'Budi'};
      final repo = _FakeAuthRepository(
        store,
        metadata: metadata,
        updateMetadata: (data) async {
          expect(
            store.get(AuthRepository.awayDayBudgetKey('account-a')),
            '750000.0',
          );
          metadata
            ..clear()
            ..addAll(data);
        },
      )..activeUserId = 'account-a';
      final container = _container(repo);
      addTearDown(container.dispose);

      final synced =
          await container.read(awayDayBudgetProvider.notifier).set(750000);

      expect(synced, isTrue);
      expect(metadata['away_day_budget_idr'], 750000);
      expect(metadata['display_name'], 'Budi');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('failed cloud preference write is retried at next login', () async {
      final store = _MemoryIdentityStore();
      final metadata = <String, dynamic>{'display_name': 'Budi'};
      var writes = 0;
      final repo = _FakeAuthRepository(
        store,
        metadata: metadata,
        updateMetadata: (data) async {
          writes++;
          if (writes == 1) throw StateError('offline');
          metadata
            ..clear()
            ..addAll(data);
        },
      );
      final container = _container(repo);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');
      final saved =
          await container.read(favoriteKeyProvider.notifier).set('arsenal');

      expect(saved, isFalse);
      expect(store.get(AuthRepository.favoriteTeamKey('account-a')), 'arsenal');
      expect(store.get(AuthRepository.prefsPendingKey('account-a')), 'true');
      expect(writes, 1);

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');

      expect(writes, 2);
      expect(metadata['favorite_team'], 'arsenal');
      expect(metadata['display_name'], 'Budi');
      expect(store.get(AuthRepository.prefsPendingKey('account-a')), isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('failed display-name write is retried at next login', () async {
      final store = _MemoryIdentityStore();
      final metadata = <String, dynamic>{};
      var writes = 0;
      final repo = _FakeAuthRepository(
        store,
        metadata: metadata,
        updateMetadata: (data) async {
          writes++;
          if (writes == 1) throw StateError('offline');
          metadata
            ..clear()
            ..addAll(data);
        },
      );
      final container = _container(repo);
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');
      final error =
          await container.read(displayNameProvider.notifier).set('Budi');

      expect(error, contains('belum tersimpan ke akun'));
      expect(store.get(AuthRepository.displayNameKey('account-a')), 'Budi');
      expect(store.get(AuthRepository.prefsPendingKey('account-a')), 'true');

      await container.read(authProvider.notifier).login('alice@mail.com', 'pw');

      expect(writes, 2);
      expect(metadata['display_name'], 'Budi');
      expect(store.get(AuthRepository.prefsPendingKey('account-a')), isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('login, register, unlock, and logout invalidate email identity',
        () async {
      final repo = _FakeAuthRepository(_MemoryIdentityStore());
      final container = _container(repo);
      addTearDown(container.dispose);

      Future<void> expectInvalidation(Future<void> Function() action) async {
        await container.read(userEmailProvider.future);
        final before = repo.emailReads;
        await action();
        await container.read(userEmailProvider.future);
        expect(repo.emailReads, before + 1);
      }

      await expectInvalidation(
        () =>
            container.read(authProvider.notifier).login('alice@mail.com', 'pw'),
      );
      await expectInvalidation(() => container
          .read(authProvider.notifier)
          .register('new@mail.com', 'password', 'password'));
      await expectInvalidation(
          () => container.read(authProvider.notifier).unlock());
      await expectInvalidation(
          () => container.read(authProvider.notifier).logout());
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
