import '../../../core/database/hive_service.dart';

abstract interface class IdentityStore {
  String? get(String key);
  Future<void> put(String key, String value);
  Future<void> delete(String key);
}

class HiveIdentityStore implements IdentityStore {
  @override
  String? get(String key) => HiveService.cache.get(key);

  @override
  Future<void> put(String key, String value) =>
      HiveService.cache.put(key, value);

  @override
  Future<void> delete(String key) => HiveService.cache.delete(key);
}
