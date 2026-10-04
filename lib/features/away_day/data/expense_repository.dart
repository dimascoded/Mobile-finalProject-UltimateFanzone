import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/app_config.dart';

class Expense {
  Expense({
    required this.title,
    required this.amountIdr,
    required this.date,
    this.countryId,
  });
  final String title;
  final double amountIdr;
  final DateTime date;
  final String? countryId; // terkait Trip (null = tanpa trip)

  String get id => date.toIso8601String();

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount': amountIdr,
        'date': date.toIso8601String(),
        'countryId': countryId,
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        title: j['title'],
        amountIdr: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date']),
        countryId: j['countryId'],
      );
}

class ExpenseRepository {
  ExpenseRepository(this._dio);
  final Dio _dio;
  static const _key = 'expenses';

  /// Kurs dengan basis IDR.
  Future<Map<String, double>> fetchRates() async {
    final res = await _dio.get(AppConfig.exchangeRateUrl);
    final rates = Map<String, dynamic>.from(res.data['rates'] as Map);
    return rates.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  List<Expense> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save(List<Expense> list) =>
      HiveService.cache.put(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
}

final expenseRepositoryProvider =
    Provider((ref) => ExpenseRepository(ref.watch(dioProvider)));
