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

  /// Parse toleran (C2): item yang field hilang atau salah tipe tidak boleh
  /// membuat seluruh daftar pengeluaran hilang.
  ///
  /// Aturannya: judul wajib (kalau kosong, pakai "Tanpa judul"), nominal
  /// non-angka jadi 0, tanggal rusak jadi epoch supaya item tetap urut.
  factory AwayDayExpense.fromJson(Map<String, dynamic> j) => AwayDayExpense(
        title: (j['title'] as String?)?.trim().isNotEmpty == true
            ? (j['title'] as String).trim()
            : 'Tanpa judul',
        amountGbp: (j['amountGbp'] as num?)?.toDouble() ?? 0,
        amountIdr: (j['amountIdr'] as num?)?.toDouble() ?? 0,
        category: AwayDayCategory.values.firstWhere(
          (e) => e.name == (j['category'] as String? ?? 'lainnya'),
          orElse: () => AwayDayCategory.lainnya,
        ),
        date: DateTime.tryParse(j['date'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        clubKey: j['clubKey'] as String?,
      );
}

class AwayDayRepository {
  static const _key = 'away_day_expenses';
  static const _budgetKey = 'away_day_budget_idr';

  List<AwayDayExpense> load() {
    final raw = HiveService.cache.get(_key);
    if (raw == null) return [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    if (decoded is! List) return [];
    final out = <AwayDayExpense>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      try {
        out.add(AwayDayExpense.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {
        continue; // lewati item rusak, pertahankan sisanya
      }
    }
    return out;
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

  Future<void> saveBudget(double idr) =>
      HiveService.cache.put(_budgetKey, '$idr');
}

final awayDayRepositoryProvider = Provider((ref) => AwayDayRepository());
