import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import 'blockchain.dart';

class ChainRepository {
  static const _key = 'passport_chain';

  List<Block> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [Blockchain.genesis()];
    return (jsonDecode(raw) as List)
        .map((e) => Block.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save(List<Block> chain) => HiveService.cache
      .put(_key, jsonEncode(chain.map((b) => b.toJson()).toList()));
}

final chainRepositoryProvider = Provider((ref) => ChainRepository());
