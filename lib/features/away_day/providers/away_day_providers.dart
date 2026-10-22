import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../../core/network/rates_provider.dart';
import '../../../core/utils/time_utils.dart';
import '../../football/providers/football_providers.dart';
import '../data/away_day_repository.dart';
import '../data/currency_convert.dart';

/// Daftar kode mata uang yang bisa dipilih pengguna saat mencatat pengeluaran
/// Away Day (diambil dari [supportedCurrencies]).
///
/// Nilai ini konstan sepanjang hidup aplikasi: dipakai sebagai daftar pilihan
/// di form pengeluaran, bukan state yang bisa berubah.
final awayDayCurrencies = supportedCurrencies.keys.toList();

/// Rates API memakai IDR sebagai basis: `rates[code]` adalah unit asing per IDR.
double? foreignToIdr(
  double amount,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return amount;
  final rate = rates?[currency];
  if (rate == null || rate == 0) return null;
  return amount / rate;
}

/// Konversi Rupiah ke mata uang asing memakai kurs berbasis IDR.
///
/// Mengembalikan null bila kurs untuk [currency] belum pernah diambil
/// (offline tanpa cache) atau bernilai nol, sehingga pemanggil bisa
/// membedakan "nominal 0" dari "kurs tidak diketahui".
double? idrToForeign(
  double idr,
  String currency,
  Map<String, double>? rates,
) {
  if (currency == 'IDR') return idr;
  final rate = rates?[currency];
  if (rate == null) return null;
  return idr * rate;
}

/// Kekcil poundsterling ke Rupiah memakai kurs berbasis IDR.
///
/// Shorthand untuk [foreignToIdr]; null bila kurs GBP tidak tersedia.
double? gbpToIdr(double gbp, Map<String, double>? rates) =>
    foreignToIdr(gbp, 'GBP', rates);

/// Ubah Rupiah ke poundsterling memakai kurs berbasis IDR.
///
/// Shorthand untuk [idrToForeign]; null bila kurs GBP tidak tersedia.
double? idrToGbp(double idr, Map<String, double>? rates) =>
    idrToForeign(idr, 'GBP', rates);

// ---------- Pengeluaran ----------

/// Notifier daftar pengeluaran Away Day.
///
/// State-nya `List<AwayDayExpense>` yang sudah terurut dari yang terbaru.
/// Sumber data ada di Hive `app_cache` (kunci `away_day_expenses`) dan
/// cerminnya di SQLite `sync_documents` (collection `away_day_expenses`);
/// setiap penulisan lewat [AwayDayRepository.save] menaikkan revisi koleksi
/// sehingga perubahannya ikut terkirim pada sinkronisasi berikutnya.
///
/// Notifier ini BUKAN `autoDispose`, jadi tidak wajib mengecek `mounted`
/// sebelum menyentuh `state` setelah `await` (aturan §3.5 hanya berlaku
/// untuk notifier `autoDispose`). Urutan eksekusinya pun disengaja: `state`
/// diperbarui dulu, baru penyimpanan ditunggu, supaya UI tidak melambat
/// saat penyimpanan lambat.
class AwayDayNotifier extends StateNotifier<List<AwayDayExpense>> {
  AwayDayNotifier(this._repo) : super(_repo.load());

  final AwayDayRepository _repo;

  /// Tambahkan satu pengeluaran baru di posisi teratas.
  ///
  /// Membentuk [AwayDayExpense] dengan `date` = sekarang (dipakai juga sebagai
  /// `id` baris), menambahkannya ke depan daftar, lalu menyimpan seluruh
  /// daftar ke Hive `away_day_expenses` + SQLite collection
  /// `away_day_expenses` lewat [AwayDayRepository.save].
  Future<void> add({
    required String title,
    required double amountGbp,
    required double amountIdr,
    required AwayDayCategory category,
    String currencyCode = 'GBP',
    double? amountForeign,
    String? clubKey,
  }) async {
    state = [
      AwayDayExpense(
        title: title,
        amountGbp: amountGbp,
        amountIdr: amountIdr,
        currencyCode: currencyCode,
        amountForeign: amountForeign,
        category: category,
        date: DateTime.now(),
        clubKey: clubKey,
      ),
      ...state,
    ];
    await _repo.save(state);
  }

  /// Perbarui pengeluaran yang sudah ada IN PLACE: posisi di daftar, `date`,
  /// dan `id` tidak berubah (tidak ada antrean hapus, tidak ada baris baru).
  ///
  /// Persist lewat jalur yang sama dengan [add] (`_repo.save`), supaya revisi
  /// koleksi naik dan sinkronisasi ikut mengirim perubahannya. Mengembalikan
  /// false kalau `id` tidak ditemukan (tidak ada perubahan apa pun).
  Future<bool> update(
    String id, {
    required String title,
    required double amountGbp,
    required double amountIdr,
    required AwayDayCategory category,
    required String currencyCode,
    required double amountForeign,
    String? clubKey,
  }) async {
    final index = state.indexWhere((e) => e.id == id);
    if (index < 0) return false;
    final next = [...state];
    next[index] = state[index].copyWith(
      title: title,
      amountGbp: amountGbp,
      amountIdr: amountIdr,
      category: category,
      currencyCode: currencyCode,
      amountForeign: amountForeign,
      clubKey: clubKey,
      clearClubKey: clubKey == null,
    );
    state = next;
    await _repo.save(state);
    return true;
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await OfflineSyncDatabase.queueDeletion('away_day_expenses', id);
    await _repo.save(state);
  }

  /// Hapus seluruh pengeluaran tanpa antrean penghapusan per item.
  ///
  /// Baris di SQLite collection `away_day_expenses` ikut tertimpa karena
  /// daftar kosong disimpan penuh lewat [AwayDayRepository.save].
  Future<void> clearAll() async {
    state = const [];
    await _repo.save(state);
  }

  /// Terapkan hasil merge sinkronisasi (S1): daftar gabungan dari server dan
  /// perangkat ini langsung disimpan ke Hive, bukan hanya dihitung.
  ///
  /// Daftar final ditulis ke Hive `app_cache` (kunci `away_day_expenses`) dan
  /// SQLite collection `away_day_expenses`, sehingga revisi koleksi naik dan
  /// sinkronisasi berikutnya tidak mengirim ulang data yang sama.
  Future<void> replaceAll(List<AwayDayExpense> list) async {
    state = list;
    await _repo.save(state);
  }
}

final awayDayProvider =
    StateNotifierProvider<AwayDayNotifier, List<AwayDayExpense>>(
  (ref) => AwayDayNotifier(ref.watch(awayDayRepositoryProvider)),
);

/// Teks pencarian pada daftar pengeluaran.
///
/// State lokal UI: di-reset ke string kosong saat provider di-dispose
/// (`autoDispose`), jadi kembali ke layar selalu mulai dari daftar penuh.
final awayDayQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Filter kategori; null = semua kategori.
///
/// State lokal UI dengan `autoDispose`: pilihan filter tidak bertahan saat
/// layar ditutup.
final awayDayCategoryFilterProvider =
    StateProvider.autoDispose<AwayDayCategory?>((ref) => null);

/// Tampilkan hanya pengeluaran milik tim favorit.
///
/// State lokal UI dengan `autoDispose`; aktifkan lewat sakelar di layar
/// Away Day.
final awayDayFavOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Hasil akhir filter + pencarian gabungan.
///
/// Provider turunan (read-only): menggabungkan [awayDayProvider] dengan
/// [awayDayQueryProvider], [awayDayCategoryFilterProvider],
/// [awayDayFavOnlyProvider], dan tim favorit dari
/// [favoriteKeyProvider]. Pencarian mencocokkan judul atau nama kategori
/// (case-insensitive); filter "favorit" hanya berlaku bila tim favorit sudah
/// dipilih. `autoDispose`: daftar hasil dihitung ulang hanya selama ada
/// yang menonton, dan tidak ada efek samping.
final awayDayFilteredProvider =
    Provider.autoDispose<List<AwayDayExpense>>((ref) {
  final q = ref.watch(awayDayQueryProvider).toLowerCase().trim();
  final cat = ref.watch(awayDayCategoryFilterProvider);
  final favOnly = ref.watch(awayDayFavOnlyProvider);
  final favKey = ref.watch(favoriteKeyProvider);

  return ref.watch(awayDayProvider).where((e) {
    if (cat != null && e.category != cat) return false;
    if (favOnly && favKey != null && e.clubKey != favKey) return false;
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.category.name.toLowerCase().contains(q);
  }).toList();
});

/// Total pengeluaran dalam Rupiah dan poundsterling.
///
/// Provider turunan dari [awayDayProvider]: menjumlahkan nominal IDR dan
/// nominal GBP yang tersimpan di setiap baris (bukan hasil konversi kurs),
/// sehingga angkanya tetap sama walau kurs offline. Tanpa efek samping dan
/// tidak `autoDispose`.
final awayDayTotalsProvider = Provider<({double idr, double gbp})>((ref) {
  var idr = 0.0;
  var gbp = 0.0;
  for (final e in ref.watch(awayDayProvider)) {
    idr += e.amountIdr;
    gbp += e.amountGbp;
  }
  return (idr: idr, gbp: gbp);
});

/// Pengeluaran per kategori untuk bar ringkas.
///
/// Provider turunan dari [awayDayProvider]: peta kategori ke total nominal
/// IDR. Kategori tanpa pengeluaran tidak muncul di peta. Tanpa efek samping.
final awayDayByCategoryProvider = Provider<Map<AwayDayCategory, double>>((ref) {
  final out = <AwayDayCategory, double>{};
  for (final e in ref.watch(awayDayProvider)) {
    out[e.category] = (out[e.category] ?? 0) + e.amountIdr;
  }
  return out;
});

// ---------- Anggaran (disimpan di Hive, bukan StateProvider) ----------

/// Notifier anggaran harian Away Day dalam Rupiah.
///
/// State-nya `double`; 0 berarti belum pernah diatur. Anggaran TIDAK
/// disimpan di Hive `app_cache` dengan kunci global, melainkan memakai
/// penyimpanan per pengguna (`away_day_budget_idr_<userId>`) supaya dua akun
/// di perangkat yang sama tidak saling menimpa, dan ikut dicerminkan ke
/// metadata Supabase lewat [AwayDayRepository.saveBudget].
///
/// Notifier tidak `autoDispose`, jadi tidak wajib cek `mounted` setelah
/// `await` (aturan §3.5 hanya untuk notifier `autoDispose`).
class BudgetNotifier extends StateNotifier<double> {
  BudgetNotifier(this._repo) : super(_repo.loadBudget());

  final AwayDayRepository _repo;

  /// Set anggaran harian baru.
  ///
  /// Nilai negatif dibulatkan menjadi 0. Menyimpan nilai final ke penyimpanan
  /// per pengguna lalu mencoba mencerminkannya ke metadata akun; nilai
  /// kembalian menandakan berhasil/tidaknya penulisan ke cloud.
  Future<bool> set(double idr) async {
    state = idr < 0 ? 0 : idr;
    return _repo.saveBudget(state);
  }
}

/// Anggaran harian Away Day dalam Rupiah.
///
/// StateProvider biasa (bukan `autoDispose`) karena nilai anggaran ikut
/// dibaca layar ringkasan; sumber penyimpanan ada di
/// [BudgetNotifier].
final awayDayBudgetProvider = StateNotifierProvider<BudgetNotifier, double>(
    (ref) => BudgetNotifier(ref.watch(awayDayRepositoryProvider)));

// ---------- Mata uang ringkasan ----------

/// Kunci Hive untuk mata uang yang dipilih pada ringkasan Away Day.
const _summaryCurrencyKey = 'away_day_summary_currency';

/// Notifier pilihan mata uang ringkasan Away Day.
///
/// State-nya `String` kode mata uang; nilai bawaan `'IDR'`. Pilihan ini
/// disimpan di Hive `app_cache` (kunci `away_day_summary_currency`) dan
/// sengaja TIDAK per pengguna: ini preferensi tampilan perangkat, bukan data
/// pribadi, jadi ikut bertahan saat logout dan tidak ikut terhapus oleh
/// [clearUserData].
///
/// Tidak `autoDispose`, jadi tidak wajib cek `mounted` setelah `await`.
class AwayDaySummaryCurrencyNotifier extends StateNotifier<String> {
  AwayDaySummaryCurrencyNotifier() : super(_load());

  static String _load() {
    final raw = HiveService.cache.get(_summaryCurrencyKey);
    if (raw == null || raw.isEmpty) return 'IDR';
    if (supportedCurrencies.containsKey(raw)) return raw;
    return 'IDR'; // ignore unknown
  }

  /// Ubah mata uang ringkasan.
  ///
  /// Kode yang tidak dikenal diabaikan (state tidak berubah). Nilai baru
  /// ditulis ke Hive `app_cache` dengan kunci `away_day_summary_currency`.
  Future<void> set(String code) async {
    if (!supportedCurrencies.containsKey(code)) return;
    state = code;
    await HiveService.cache.put(_summaryCurrencyKey, code);
  }
}

/// Mata uang aktif untuk ringkasan Away Day (kode `'GBP'`, `'IDR'`, dan
/// seterusnya).
///
/// Menyimpan pilihan pengguna di Hive `app_cache`; nilai tak dikenal akan
/// kembali ke `'IDR'`. Tanpa efek samping selain penulisan kunci Hive.
final awayDaySummaryCurrencyProvider =
    StateNotifierProvider<AwayDaySummaryCurrencyNotifier, String>(
  (ref) => AwayDaySummaryCurrencyNotifier(),
);

/// Ringkasan total pengeluaran dalam mata uang yang dipilih.
///
/// Provider turunan: menggabungkan [awayDayProvider],
/// [awayDaySummaryCurrencyProvider], dan kurs dari [ratesProvider]. Hasilnya
/// [AwayDaySummary] berisi total dalam mata uang terpilih, total dalam IDR,
/// serta jumlah baris yang perlu fallback ke nominal IDR dan jumlah baris
/// yang dilewati karena kurs tidak tersedia. Tanpa efek samping.
final awayDaySummaryProvider = Provider<AwayDaySummary>((ref) {
  final items = ref.watch(awayDayProvider);
  final selected = ref.watch(awayDaySummaryCurrencyProvider);
  final rates = ref.watch(ratesProvider).valueOrNull?.rates;
  return summarizeExpenses(items, selected, rates);
});

// ---------- Jam dunia (rubrik: WIB / WITA / WIT / London) ----------

/// Zona waktu yang dipakai label jam dunia di layar Away Day.
///
/// State lokal UI dengan `autoDispose`; nilai bawaan `'WIB'`.
final awayDayClockZoneProvider =
    StateProvider.autoDispose<String>((ref) => 'WIB');

/// Kota Indonesia yang dipilih; memilih kota menetapkan zona waktunya.
///
/// State lokal UI dengan `autoDispose`; null berarti belum ada pilihan
/// manual sehingga zona mengikuti [awayDayClockZoneProvider].
final awayDayClockIndoCityProvider =
    StateProvider.autoDispose<String?>((ref) => null);

/// Semua klub Premier League berbasis di Inggris, jadi zona yang relevan adalah
/// WIB, WITA, WIT, dan London (Europe/London, DST ikut dihitung oleh TimeUtils).
///
/// Provider stream `autoDispose`: memancarkan peta zona -> waktu lokal setiap
/// detik, dan berhenti otomatis saat tidak ada layar yang menonton (hemat
/// baterai). Perhitungan memakai satu titik waktu UTC yang sama untuk semua
/// zona, jadi jam di empat kota selalu konsisten. Tanpa efek samping.
final worldClockProvider =
    StreamProvider.autoDispose<Map<String, DateTime>>((ref) async* {
  while (true) {
    final utc = TimeUtils.nowUtc();
    yield {
      'WIB': TimeUtils.wib(utc),
      'WITA': TimeUtils.wita(utc),
      'WIT': TimeUtils.wit(utc),
      'London': TimeUtils.london(utc),
    };
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Kurs GBP per 1 Rupiah untuk ringkasan (null bila belum pernah ada cache).
///
/// Provider turunan dari [ratesProvider]: mengembalikan `rates['GBP']` atau
/// null saat kurs belum pernah berhasil diambil. Tanpa efek samping.
final gbpRateProvider = Provider<double?>((ref) {
  final snap = ref.watch(ratesProvider).valueOrNull;
  return snap?.gbpPerIdr;
});
