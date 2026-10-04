import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';

enum AwayDayCategory { tiket, hotel, transport, merchandise, makanan, lainnya }

class AwayDayExpense {
  AwayDayExpense({
    required this.title,
    required this.amountGbp,
    required this.amountIdr,
    required this.category,
    required this.date,
    this.clubKey,
  });
  final String title;
  final double amountGbp;
  final double amountIdr;
  final AwayDayCategory category;
  final DateTime date;
  final String? clubKey;

  String get id => date.toIso8601String();

  Map<String, dynamic> toJson() => {
        'title': title,
        'amountGbp': amountGbp,
        'amountIdr': amountIdr,
        'category': category.name,
        'date': date.toIso8601String(),
        'clubKey': clubKey,
      };

  factory AwayDayExpense.fromJson(Map<String, dynamic> j) => AwayDayExpense(
        title: j['title'],
        amountGbp: (j['amountGbp'] as num).toDouble(),
        amountIdr: (j['amountIdr'] as num).toDouble(),
        category: AwayDayCategory.values.firstWhere(
          (e) => e.name == (j['category'] as String? ?? 'lainnya'),
          orElse: () => AwayDayCategory.lainnya,
        ),
        date: DateTime.parse(j['date']),
        clubKey: j['clubKey'],
      );
}

class AwayDayRepository {
  static const _key = 'away_day_expenses';
  static const _budgetKey = 'away_day_budget_idr';

  List<AwayDayExpense> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => AwayDayExpense.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<AwayDayExpense> list) => HiveService.cache.put(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );

  /// Anggaran harian dalam Rupiah. 0 berarti belum diatur.
  double loadBudget() {
    final raw = HiveService.cache.get(_budgetKey);
    if (raw == null) return 0;
    return double.tryParse(raw) ?? 0;
  }

  Future<void> saveBudget(double idr) => HiveService.cache.put(_budgetKey, '$idr');
}

final awayDayRepositoryProvider = Provider((ref) => AwayDayRepository());