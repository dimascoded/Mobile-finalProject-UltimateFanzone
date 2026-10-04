import 'dart:convert';

class ItineraryItem {
  const ItineraryItem({required this.time, required this.activity, this.cost});
  final String time, activity;
  final double? cost; // dalam mata uang negara tujuan
}

class ItineraryDay {
  const ItineraryDay({required this.day, required this.title, required this.items});
  final int day;
  final String title;
  final List<ItineraryItem> items;
  double get total => items.fold(0.0, (s, i) => s + (i.cost ?? 0));
}

/// Mengubah keluaran Gemini (JSON) menjadi model. Dart murni -> mudah di-unit-test.
/// Mengembalikan null jika bukan JSON valid (UI memakai teks mentah sebagai cadangan).
class ItineraryParser {
  static List<ItineraryDay>? parse(String raw) {
    final s = raw.trim();
    // Gemini sering membungkus dengan ```json ... ``` -> ambil dari '[' pertama s/d ']' terakhir.
    final a = s.indexOf('[');
    final b = s.lastIndexOf(']');
    if (a == -1 || b <= a) return null;
    try {
      final decoded = jsonDecode(s.substring(a, b + 1));
      if (decoded is! List) return null;
      final days = <ItineraryDay>[];
      for (final d in decoded) {
        if (d is! Map) continue;
        final items = <ItineraryItem>[];
        for (final it in (d['items'] as List? ?? const [])) {
          if (it is! Map) continue;
          items.add(ItineraryItem(
            time: '${it['time'] ?? ''}',
            activity: '${it['activity'] ?? ''}',
            cost: _toDouble(it['cost']),
          ));
        }
        days.add(ItineraryDay(
          day: (d['day'] as num?)?.toInt() ?? days.length + 1,
          title: '${d['title'] ?? ''}',
          items: items,
        ));
      }
      return days.isEmpty ? null : days;
    } catch (_) {
      return null;
    }
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
  }
}
