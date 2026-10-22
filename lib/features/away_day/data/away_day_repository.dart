import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/hive_service.dart';
import '../../../core/database/offline_sync_database.dart';
import '../../auth/data/auth_repository.dart';

/// Kategori pengeluaran away day (dipakai juga sebagai label saat parsing
/// struk pada fitur Lens).
enum AwayDayCategory { tiket, hotel, transport, merchandise, makanan, lainnya }

/// Satu pengeluaran away day (tiket, hotel, makan, merch, ...).
///
/// Menyimpan tiga nilai nominal sekaligus: [amountForeign] (nominal asli
/// dalam [currencyCode]), [amountIdr] (nilai Rupiah saat disimpan), dan
/// [amountGbp] (padanan poundsterling untuk ringkasan).
class AwayDayExpense {
  /// Membuat expense. [amountForeign] otomatis mengikuti [amountGbp] bila
  /// tidak diberikan, jadi pemanggil lama tidak perlu mengubah apa pun.
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

  /// Judul bebas, mis. "Tiket Arsenal vs Chelsea".
  final String title;

  /// Nominal dalam poundsterling (dihitung dari [amountIdr] saat disimpan).
  final double amountGbp;

  /// Nominal dalam Rupiah.
  final double amountIdr;

  /// Kode mata uang nominal asli (default `GBP`).
  final String currencyCode;

  /// Nominal asli dalam [currencyCode].
  final double amountForeign;

  /// Kategori pengeluaran.
  final AwayDayCategory category;

  /// Tanggal pengeluaran; sekaligus menjadi identitas baris (lihat [id]).
  final DateTime date;

  /// Kode klub yang dikunjungi (bisa null untuk pengeluaran biasa).
  final String? clubKey;

  /// Identitas expense, diturunkan dari [date].
  ///
  /// Sengaja memakai tanggal (bukan UUID) supaya edit menimpa baris yang
  /// sama dan [copyWith] tidak pernah mengubah [date].
  String get id => date.toIso8601String();

  /// Salinan dengan field yang boleh diubah saat edit.
  ///
  /// `date` TIDAK punya parameter supaya `id` (turunan `date`) tidak pernah
  /// berubah — edit selalu menimpa expense yang sama, bukan membuat baris baru.
  AwayDayExpense copyWith({
    String? title,
    double? amountGbp,
    double? amountIdr,
    String? currencyCode,
    double? amountForeign,
    AwayDayCategory? category,
    String? clubKey,
    bool clearClubKey = false,
  }) {
    return AwayDayExpense(
      title: title ?? this.title,
      amountGbp: amountGbp ?? this.amountGbp,
      amountIdr: amountIdr ?? this.amountIdr,
      currencyCode: currencyCode ?? this.currencyCode,
      amountForeign: amountForeign ?? this.amountForeign,
      category: category ?? this.category,
      date: date,
      clubKey: clearClubKey ? null : (clubKey ?? this.clubKey),
    );
  }

  /// Serialisasi ke JSON untuk disimpan di Hive/SQLite.
  ///
  /// Bentuk kunci harus sama dengan yang dibaca [AwayDayExpense.fromJson].
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
  ///
  /// Sumber datanya adalah koleksi Hive `away_day_expenses` (box `app_cache`)
  /// yang disalin ke tabel SQLite `sync_documents` untuk sinkronisasi.
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

/// Repository daftar pengeluaran away day.
///
/// Data disimpan pada koleksi Hive `away_day_expenses` (box `app_cache`) dan
/// dicerminkan ke tabel SQLite `sync_documents` dengan `collection =
/// 'away_day_expenses'` supaya bisa disinkronkan ke server (koleksi sinkron:
/// `away_day_expenses`, `passport_chain`, `score_predictions`). Penghapusan
/// satu baris dicatat di tabel `sync_deletions`.
class AwayDayRepository {
  /// Nama koleksi (dipakai juga sebagai kunci Hive dan kolom `collection`).
  static const _key = 'away_day_expenses';

  /// Repository tanpa [AuthRepository]: anggaran tidak bisa dibaca/simpan.
  AwayDayRepository([this._auth]);

  /// Auth aktif; dipakai untuk membaca/menulis anggaran per-pengguna.
  final AuthRepository? _auth;

  /// Muat seluruh pengeluaran dari Hive box `app_cache`, kunci
  /// `away_day_expenses`.
  ///
  /// Isinya adalah JSON array. Data yang rusak (bukan JSON, bukan array, atau
  /// item dengan field salah) dilewati, bukan menggagalkan seluruh daftar.
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

  /// Simpan seluruh daftar pengeluaran.
  ///
  /// Menulis ke Hive box `app_cache` (kunci `away_day_expenses`) sekaligus
  /// ke tabel SQLite `sync_documents` (collection `away_day_expenses`) lewat
  /// [OfflineSyncDatabase.persist], sehingga revisi sinkronisasi naik dan
  /// data terkirim ke server.
  Future<void> save(List<AwayDayExpense> list) => OfflineSyncDatabase.persist(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );

  /// Anggaran harian dalam Rupiah. 0 berarti belum diatur.
  ///
  /// Sumber: nilai lokal di Hive (kunci `away_day_budget_idr_<userId>`,
  /// termasuk nilai legacy global yang diadopsi); kalau belum ada, diambil
  /// dari metadata cloud `away_day_budget_idr` lalu ditulis balik ke Hive.
  /// Tanpa user id (belum masuk) hasilnya 0.
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

  /// Simpan anggaran harian (Rupiah) secara lokal dan ke metadata cloud.
  ///
  /// Nilai lokal disimpan pada kunci Hive `away_day_budget_idr_<userId>`;
  /// nilai cloud disimpan pada metadata `away_day_budget_idr` (dibulatkan ke
  /// integer). Mengembalikan false bila tidak ada user id atau penulisan
  /// cloud gagal.
  Future<bool> saveBudget(double idr) async {
    final auth = _auth;
    if (auth?.currentUserId == null) return false;
    await auth!.writeUserScopedValue('away_day_budget_idr', '$idr');
    return auth.saveProfilePrefs(budgetIdr: idr.round());
  }
}

/// Repository pengeluaran away day yang terikat pada pengguna aktif.
final awayDayRepositoryProvider =
    Provider((ref) => AwayDayRepository(ref.watch(authRepositoryProvider)));
