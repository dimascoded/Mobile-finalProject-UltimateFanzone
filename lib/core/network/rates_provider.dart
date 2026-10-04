import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/dio_client.dart';
import '../utils/app_config.dart';

final ratesProvider = FutureProvider<Map<String, double>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get(AppConfig.exchangeRateUrl);
  final rates = Map<String, dynamic>.from(res.data['rates'] as Map);
  return rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
});