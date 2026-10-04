import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import 'models.dart';

class CountryRepository {
  Future<List<Country>> load() async {
    final raw = await rootBundle.loadString('assets/data/countries.json');
    return (jsonDecode(raw) as List)
        .map((e) => Country.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class TripRepository {
  static const _key = 'active_trip';

  Trip? load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return null;
    return Trip.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> save(Trip t) => HiveService.cache.put(_key, jsonEncode(t.toJson()));
  Future<void> clear() => HiveService.cache.delete(_key);
}

final countryRepositoryProvider = Provider((ref) => CountryRepository());
final tripRepositoryProvider = Provider((ref) => TripRepository());
