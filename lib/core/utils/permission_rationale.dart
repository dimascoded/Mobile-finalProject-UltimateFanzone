import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/hive_service.dart';

/// Menyimpan izin mana yang sudah dijelaskan ke pengguna (sekali per jenis izin).
class PermissionRationaleNotifier extends StateNotifier<Set<String>> {
  PermissionRationaleNotifier() : super(_load());
  static const _key = 'permission_rationale';

  static Set<String> _load() {
    final raw = HiveService.cache.get(_key);
    return raw == null ? <String>{} : Set<String>.from(jsonDecode(raw));
  }

  Future<void> accept(String k) async {
    state = {...state, k};
    await HiveService.cache.put(_key, jsonEncode(state.toList()));
  }
}

final permissionRationaleProvider =
    StateNotifierProvider<PermissionRationaleNotifier, Set<String>>(
        (ref) => PermissionRationaleNotifier());
