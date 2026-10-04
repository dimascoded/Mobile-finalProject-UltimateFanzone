import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  static const _boxName = 'app_cache';
  static late Box<String> cache;

  static Future<void> init() async {
    await Hive.initFlutter();
    cache = await Hive.openBox<String>(_boxName);
  }
}
