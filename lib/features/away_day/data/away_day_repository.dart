import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../auth/data/auth_repository.dart';

enum AwayDayCategory { tiket, hotel, transport, merchandise, makanan, lainnya }

class AwayDayExpense {
  AwayDayExpense({
    required this.title,
    required this.amountGbp,
    required this.amountIdr,
    required this.category,
    required this.date,
    this.currencyCode = 'GBP',
    double? amountForeign,
    this.clubKey,
  }) : amountForeign = amountForeign ?? amountGbp;
  final String title;
  final double amountGbp;
  final double amountIdr;
  final String currencyCode;
  final double amountForeign;
  final AwayDayCategory category;
  final DateTime date;
  final String? clubKey;

  String get id => date.toIso8601String();

  Map<String, dynamic> toJson() => {
        'title': title,
        'amountGbp': amountGbp,
        'amountIdr': amountIdr,
        'currencyCode': currencyCode,
        'amountForeign': amountForeign,
        'category': category.name,
        'date': date.toIso8601String(),
        'clubKey': clubKey,
      };

  /// Parse toleran (C2): item yang field hilang atau salah tipe tidak boleh
  /// membuat seluruh daftar pengeluaran hilang.
  ///
  /// Aturannya: judul wajib (kalau kosong, pakai "Tanpa judul"), nominal
  /// non-angka jadi 0, tanggal rusak jadi epoch supaya item tetap urut.
  factory AwayDayExpense.fromJson(Map<String, dynamic> j) {
    final amountGbp = (j['amountGbp'] as num?)?.toDouble() ?? 0;
    return AwayDayExpense(
      title: (j['title'] as String?)?.trim().isNotEmpty == true
          ? (j['title'] as String).trim()
          : 'Tanpa judul',
      amountGbp: amountGbp,
      amountIdr: (j['amountIdr'] as num?)?.toDouble() ?? 0,
      currencyCode: j['currencyCode'] as String? ?? 'GBP',
      amountForeign: (j['amountForeign'] as num?)?.toDouble() ?? amountGbp,
      category: AwayDayCategory.values.firstWhere(
        (e) => e.name == (j['category'] as String? ?? 'lainnya'),
        orElse: () => AwayDayCategory.lainnya,
      ),
      date: DateTime.tryParse(j['date'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clubKey: j['clubKey'] as String?,
    );
  }
}

class AwayDayRepository {
  static const _key = 'away_day_expenses';

  AwayDayRepository([this._auth]);

  final AuthRepository? _auth;

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

  Future<void> save(List<AwayDayExpense> list) => OfflineSyncDatabase.persist(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );

  /// Anggaran harian dalam Rupiah. 0 berarti belum diatur.
  double loadBudget() {
    final auth = _auth;
    if (auth?.currentUserId == null) return 0;
    final local = auth!.readUserScopedValue('away_day_budget_idr');
    if (local != null) return double.tryParse(local) ?? 0;
    final cloud = auth.cloudBudgetIdr();
    if (cloud == null) return 0;
    unawaited(
        auth.writeUserScopedValue('away_day_budget_idr', cloud.toString()));
    return cloud.toDouble();
  }

  Future<bool> saveBudget(double idr) async {
    final auth = _auth;
    if (auth?.currentUserId == null) return false;
    await auth!.writeUserScopedValue('away_day_budget_idr', '$idr');
    return auth.saveProfilePrefs(budgetIdr: idr.round());
  }
}

final awayDayRepositoryProvider =
    Provider((ref) => AwayDayRepository(ref.watch(authRepositoryProvider)));
