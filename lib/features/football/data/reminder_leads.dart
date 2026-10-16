import '../../../core/utils/app_config.dart';

/// Lead time paling awal yang diizinkan: 7 hari sebelum kickoff.
const maxLeadMinutes = 7 * 24 * 60;

/// Jumlah maksimal pengingat (slot notifikasi) per laga. Harus sama dengan
/// `NotificationService.kickoffSlotCount`.
const maxReminderSlots = 3;

/// Lead time bawaan, mengikuti `--dart-define=KICKOFF_REMINDER_MINUTES`.
const defaultLeads = <int>[AppConfig.kickoffReminderMinutes];

/// Rapikan daftar lead time (menit): buang nilai <= 0 atau > [maxLeadMinutes],
/// hilangkan duplikat, urutkan menurun (pengingat paling awal di depan), lalu
/// sisakan paling banyak [maxReminderSlots] entri. Hasil kosong diizinkan:
/// berarti pengingat nonaktif.
List<int> normalizeLeads(Iterable<int> input) {
  final unique = <int>{
    for (final minutes in input)
      if (minutes > 0 && minutes <= maxLeadMinutes) minutes,
  };
  final sorted = unique.toList()..sort((a, b) => b.compareTo(a));
  return sorted.take(maxReminderSlots).toList();
}

/// Ubah jumlah menit ke teks Indonesia: 15 -> '15 menit', 60 -> '1 jam',
/// 90 -> '1 jam 30 menit', 1440 -> '1 hari', 1500 -> '1 hari 1 jam'.
String formatLead(int minutes) {
  final days = minutes ~/ (24 * 60);
  final hours = (minutes % (24 * 60)) ~/ 60;
  final mins = minutes % 60;
  final parts = <String>[
    if (days > 0) '$days hari',
    if (hours > 0) '$hours jam',
    if (mins > 0) '$mins menit',
  ];
  if (parts.isEmpty) return '0 menit';
  return parts.join(' ');
}

/// Isi notifikasi pengingat. Lead time sehari ke atas (kickoff jauh) memakai
/// bentuk "Mulai ... lagi" karena "Mulai dalam 1 hari lagi" terdengar janggal.
String leadBody(int minutes) => minutes >= 24 * 60
    ? 'Mulai ${formatLead(minutes)} lagi'
    : 'Mulai dalam ${formatLead(minutes)}';

/// Konversi input pengguna ke menit. [unit] salah satu dari 'menit', 'jam',
/// atau 'hari'; unit yang tidak dikenal menghasilkan 0 (lalu dibuang oleh
/// [normalizeLeads]).
int leadFromInput(int value, String unit) {
  switch (unit) {
    case 'menit':
      return value;
    case 'jam':
      return value * 60;
    case 'hari':
      return value * 24 * 60;
    default:
      return 0;
  }
}

/// Hitung pengingat yang benar-benar bisa dijadwalkan untuk satu laga.
///
/// [slot] adalah posisi di daftar hasil [normalizeLeads] (bukan posisi di
/// hasil filter), sehingga nomor slot tetap stabil walau pengingat lain sudah
/// lewat waktunya. Entri yang waktunya tidak lagi setelah [nowUtc] dibuang.
List<(int slot, int minutes, DateTime fireUtc)> plannedReminders(
  DateTime kickoffUtc,
  List<int> leads,
  DateTime nowUtc,
) {
  final kickoff = kickoffUtc.toUtc();
  final now = nowUtc.toUtc();
  final normalized = normalizeLeads(leads);
  final planned = <(int slot, int minutes, DateTime fireUtc)>[];
  for (var slot = 0; slot < normalized.length; slot++) {
    final minutes = normalized[slot];
    final fireUtc = kickoff.subtract(Duration(minutes: minutes));
    if (!fireUtc.isAfter(now)) continue;
    planned.add((slot, minutes, fireUtc));
  }
  return planned;
}
