import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/hive_service.dart';
import '../utils/app_config.dart';
import 'dio_client.dart';

/// Kurs mata uang asing -> IDR untuk Away Day dan Lens.
///
/// exchangerate-api.com v4 dipanggil dengan basis `IDR`, jadi `rates['GBP']`
/// berarti "GBP per 1 Rupiah" dan konversinya membagi, bukan mengali.
///
/// C2: kurs disimpan di Hive dengan cap waktu supaya konversi GBP, USD, dan EUR
/// tetap bisa dipakai saat offline. Cache lama tetap dipakai walau kedaluwarsa
/// — lebih baik menampilkan kurs tersimpan daripada menampilkan "Rp 0".
class RatesSnapshot {
  const RatesSnapshot(this.rates, this.fetchedAt, {this.fromCache = false});

  final Map<String, double> rates;

  /// Waktu pengambilan terakhir; null hanya bila tidak pernah ada respons.
  final DateTime? fetchedAt;

  /// true bila yang dipakai berasal dari Hive, bukan request baru.
  final bool fromCache;

  double? get gbpPerIdr => rates['GBP'];

  Map<String, dynamic> toJson() =>
      {'rates': rates, 'fetchedAt': fetchedAt?.toIso8601String()};

  static RatesSnapshot fromJson(Map<String, dynamic> j) {
    final raw = j['rates'];
    final out = <String, double>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num && v.isFinite && v != 0) {
          out[e.key.toString()] = v.toDouble();
        }
      }
    }
    return RatesSnapshot(
      out,
      DateTime.tryParse(j['fetchedAt'] as String? ?? ''),
      fromCache: true,
    );
  }
}

/// Baca cache kurs yang tersimpan. `null` bila belum pernah ada respons
/// sukses atau isinya rusak.
RatesSnapshot? readCachedRates() {
  final raw = HiveService.cache.get('exchange_rates');
  if (raw == null) return null;
  try {
    final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final s = RatesSnapshot.fromJson(j);
    return s.rates.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

Future<void> writeCachedRates(RatesSnapshot s) async {
  await HiveService.cache.put('exchange_rates', jsonEncode(s.toJson()));
}

final ratesProvider = FutureProvider<RatesSnapshot>((ref) async {
  // Cache dibaca lebih dulu supaya offline tidak menunggu timeout.
  final cached = readCachedRates();
  try {
    final dio = ref.watch(dioProvider);
    final res = await dio.get(AppConfig.exchangeRateUrl);
    final raw = Map<String, dynamic>.from(res.data['rates'] as Map);
    final rates = <String, double>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is num && v.isFinite && v != 0) {
        rates[e.key.toString()] = v.toDouble();
      }
    }
    if (rates.isEmpty && cached != null) return cached;
    final fresh = RatesSnapshot(rates, DateTime.now());
    await writeCachedRates(fresh);
    return fresh;
  } catch (_) {
    if (cached != null) return cached;
    rethrow;
  }
});
