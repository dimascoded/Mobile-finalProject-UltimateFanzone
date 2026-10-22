import '../../away_day/data/away_day_repository.dart';
import '../../football/data/models.dart';
import 'price_parser.dart';

/// Jenis dokumen yang dipindai: karcis pertandingan atau struk belanja.
enum DocKind { ticket, receipt }

/// Satu kandidat nominal beserta [line] asal dan [score]-nya.
///
/// [score] adalah skor relevansi (higher is better): baris bertanda "total"
/// mendapat nilai tertinggi, baris pajak/cash mendapat penalti.
class AmountCandidate {
  /// Membuat kandidat nominal.
  const AmountCandidate(this.amount, this.line, this.score);

  /// Nilai nominal hasil parse.
  final double amount;

  /// Baris teks asal.
  final String line;

  /// Skor relevansi baris terhadap nominal total.
  final double score;
}

/// Hasil parsing dokumen OCR. Semua field murni data (tanpa Flutter).
class ReceiptDraft {
  /// Membuat draf hasil parsing.
  const ReceiptDraft({
    required this.kind,
    required this.title,
    required this.currency,
    required this.currencyGuessed,
    required this.amount,
    required this.candidates,
    required this.category,
    required this.clubs,
    required this.documentDate,
    required this.matchId,
  });

  /// Jenis dokumen yang terdeteksi (tiket atau struk).
  final DocKind kind;

  /// Judul yang dihasilkan, mis. "Tiket Arsenal vs Chelsea".
  final String title;

  /// Kode mata uang nominal.
  final String currency;

  /// True bila mata uang ditebak (bukan ditemukan lewat simbol/kode).
  final bool currencyGuessed;

  /// Nominal terbaik (kandidat pertama); null bila tidak ada angka valid.
  final double? amount;

  /// Kandidat nominal lain, sudah diurutkan dari yang paling relevan.
  final List<AmountCandidate> candidates;

  /// Kategori Away Day yang disarankan.
  final AwayDayCategory category;

  /// Klub yang terdeteksi di dokumen.
  final List<PlClub> clubs;

  /// Tanggal di dokumen; null bila tidak ada pola tanggal yang dikenali.
  final DateTime? documentDate;

  /// Id laga yang cocok dengan tiket; null bila tidak terpetakan.
  final int? matchId;
}

/// Cocokkan teks OCR dengan daftar klub lewat [PlClub.isTeam].
///
/// Kode tim ("ARS", "MCI") sering berdiri sendiri di struk, jadi TLA dicocokkan
/// per token. Pencocokan token memakai batas kata supaya "ARS" tidak ikut
/// cocok di dalam kata lain; alias nama tetap pakai [PlClub.isTeam] yang sudah
/// menoleransi akhiran "FC"/"AFC".
///
/// Club yang ditemukan lebih dulu wins: setiap klub hanya dicatat sekali.
List<PlClub> detectClubs(String text, List<PlClub> clubs) {
  final found = <PlClub>[];
  for (final line in text.split('\n')) {
    final clean = line.trim();
    if (clean.isEmpty) continue;
    final tokens = clean
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.toUpperCase())
        .toSet();
    for (final c in clubs) {
      if (found.contains(c)) continue;
      final byTla = tokens.contains(c.tla.toUpperCase());
      if (byTla || c.isTeam(clean, null)) found.add(c);
    }
  }
  return found;
}

/// Pola angka (dipakai baris demi baris).
final _number = RegExp(r'\d[\d.,]*\d|\d');

/// Pola huruf, dipakai untuk menilai apakah sebuah baris layak jadi judul.
final _letters = RegExp(r'[A-Za-z]');

/// Kata "vs"/"v." penanda dua tim (dipakai untuk deteksi tiket).
final _vsToken = RegExp(r'\bvs?\b\.?', caseSensitive: false);

/// Kata kunci tiket (blok, baris, kursi, gerbang, admission, ticket).
final _ticketWord = RegExp(
    r'\b(block|row|seat|gate|stand|admission|ticket)s?\b',
    caseSensitive: false);

/// Penanda Rupiah ("Rp", dengan atau tanpa titik).
final _rp = RegExp(r'\brp\.?', caseSensitive: false);

/// Kata kunci baris total.
final _totalRe = RegExp(
    r'\b(total|grand total|total bayar|amount due|balance due|jumlah|ticket price|price)\b',
    caseSensitive: false);

/// Kata kunci baris pembayaran tunai/kartu (kandidat nominal yang salah).
final _cashRe = RegExp(
    r'\b(cash|tunai|change|kembali|tendered|paid|card|visa|mastercard|debit)\b',
    caseSensitive: false);

/// Kata kunci baris pajak atau biaya layanan.
final _taxRe = RegExp(r'\b(vat|tax|ppn|service|tip)\b', caseSensitive: false);

/// Baris yang jelas bukan nominal (nomor bangku, blok, telepon, dsb).
final _lineSkipRe = RegExp(
    r'\b(block|row|seat|gate|section|table|tel|phone|telp|wa)\b'
    r'|\border\s*no\b|\breceipt\s*no\b|\binvoice\s*no\b',
    caseSensitive: false);

/// Potongan teks yang bukan nominal: tanggal, jam, dan persentase.
final _excludedPatterns = <RegExp>[
  RegExp(r'\b\d{1,2}/\d{1,2}/\d{2,4}\b'), // dd/mm/yyyy
  RegExp(r'\b\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4}\b'), // dd Mon yyyy
  RegExp(r'\b\d{4}-\d{1,2}-\d{1,2}\b'), // yyyy-mm-dd
  RegExp(r'\b\d{1,2}:\d{2}\b'), // hh:mm
  RegExp(r'\d[\d.,]*\s*%'), // persentase
];

/// Nama bulan Inggris (3 huruf) ke nomor bulan.
const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Parse satu dokumen OCR menjadi [ReceiptDraft].
///
/// Alur: deteksi klub → tentukan jenis dokumen (tiket/struk) → tebak mata
/// uang → kumpulkan kandidat nominal → tentukan kategori → cari tanggal →
/// petakan ke laga bila dokumennya tiket.
///
/// Parameter:
/// - [ocrText]: hasil OCR mentah.
/// - [clubs]: daftar klub untuk pencocokan (dari `assets/data/pl_clubs.json`).
/// - [matches]: daftar laga untuk memetakan tiket ke [ReceiptDraft.matchId].
/// - [forceKind]: memaksa jenis dokumen, melewati deteksi otomatis.
///
/// Kandidat nominal dibatasi tiga ambil; nominal terbaik dipakai sebagai
/// [ReceiptDraft.amount].
ReceiptDraft parseReceipt(
  String ocrText, {
  required List<PlClub> clubs,
  List<FootballMatch> matches = const [],
  DocKind? forceKind,
}) {
  final found = detectClubs(ocrText, clubs);
  final kind = _detectKind(ocrText, found, forceKind);
  final (currency, guessed) = _detectCurrency(ocrText);
  final candidates = _amountCandidates(ocrText, currency);
  final category =
      kind == DocKind.ticket ? AwayDayCategory.tiket : _detectCategory(ocrText);
  final date = _detectDate(ocrText);
  return ReceiptDraft(
    kind: kind,
    title: _buildTitle(kind, ocrText, found, category),
    currency: currency,
    currencyGuessed: guessed,
    amount: candidates.isEmpty ? null : candidates.first.amount,
    candidates: candidates,
    category: category,
    clubs: found,
    documentDate: date,
    matchId: _detectMatch(found, matches, date, kind),
  );
}

/// Tentukan jenis dokumen: tiket kalau ada dua klub + kata "vs", atau ada
/// kata tiket (block/row/seat/gate/stand/admission/ticket).
///
/// [force] (dari `forceKind`) selalu menang dan menutupi deteksi otomatis.
DocKind _detectKind(String text, List<PlClub> found, DocKind? force) {
  if (force != null) return force;
  final hasTwoClubs = found.length >= 2;
  final hasVs = _vsToken.hasMatch(text);
  final hasTicketWord = _ticketWord.hasMatch(text);
  return (hasTwoClubs && hasVs) || hasTicketWord
      ? DocKind.ticket
      : DocKind.receipt;
}

bool _hasWord(String text, String word) => RegExp(
      '\\b${RegExp.escape(word)}\\b',
      caseSensitive: false,
    ).hasMatch(text);

/// Tebak mata uang dokumen: simbol/kode yang eksplisit lebih dulu
/// (£/$/€/Rp atau GBP/USD/EUR/IDR), lalu kata kunci berbahasa Indonesia
/// ("total bayar", "tunai", "kembali", "ppn", "jl.").
///
/// Mengembalikan `(kode, tebak)`; boolean menandai bahwa mata uang ditebak
/// karena tidak ada penanda eksplisit. Kalau tidak ada petunjuk sama sekali,
/// default-nya GBP (karena liga Premier).
(String, bool) _detectCurrency(String text) {
  if (text.contains('£') || _hasWord(text, 'GBP')) return ('GBP', false);
  if (text.contains(r'$') || _hasWord(text, 'USD')) return ('USD', false);
  if (text.contains('€') || _hasWord(text, 'EUR')) return ('EUR', false);
  if (_rp.hasMatch(text) || _hasWord(text, 'IDR')) return ('IDR', false);

  final lower = text.toLowerCase();
  final idCues = <bool>[
    lower.contains('total bayar'),
    lower.contains('tunai'),
    lower.contains('kembali'),
    lower.contains('ppn'),
    lower.contains('jl.'),
    _rp.hasMatch(text),
  ];
  return idCues.any((v) => v) ? ('IDR', true) : ('GBP', true);
}

/// Kumpulkan kandidat nominal dari setiap baris OCR.
///
/// Baris yang berisi data non-harga (nomor blok/kursi/karcis, nomor
/// telepon, nomor struk/invoice) dilewati. Angka tanggal, jam, persentase,
/// dan angka yang diikuti "x" (jumlah barang) juga dibuang. Nilai di-parse
/// dengan [PriceParser.parse] memakai mata uang dokumen, lalu kandidat diberi
/// skor relevansi dan diurutkan; hanya tiga teratas yang dikembalikan.
List<AmountCandidate> _amountCandidates(String text, String currency) {
  final out = <AmountCandidate>[];
  for (final line in text.split('\n')) {
    if (_lineSkipRe.hasMatch(line)) continue;
    final ranges = _excludedRanges(line);
    for (final m in _number.allMatches(line)) {
      if (_inRanges(m.start, m.end, ranges)) continue;
      final raw = m.group(0)!;
      if (_digitCount(raw) >= 9) continue;
      if (_isPercentage(line, m.end)) continue;
      if (_isQuantity(line, m.start, m.end)) continue;
      final amount = PriceParser.parse(raw, currency);
      if (amount == null || amount <= 0) continue;
      out.add(AmountCandidate(amount, line.trim(), _scoreLine(line, raw)));
    }
  }
  out.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : b.amount.compareTo(a.amount);
  });
  return out.take(3).toList();
}

bool _inRanges(int start, int end, List<List<int>> ranges) =>
    ranges.any((r) => start < r[1] && end > r[0]);

List<List<int>> _excludedRanges(String line) {
  final out = <List<int>>[];
  for (final re in _excludedPatterns) {
    for (final m in re.allMatches(line)) {
      out.add([m.start, m.end]);
    }
  }
  return out;
}

int _digitCount(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '').length;

bool _isPercentage(String line, int end) {
  for (var i = end; i < line.length; i++) {
    if (line[i] == ' ') continue;
    return line[i] == '%';
  }
  return false;
}

bool _isQuantity(String line, int start, int end) {
  var p = start - 1;
  while (p >= 0 && line[p] == ' ') {
    p--;
  }
  if (p >= 0 && (line[p] == 'x' || line[p] == 'X')) return true;
  var n = end;
  while (n < line.length && line[n] == ' ') {
    n++;
  }
  return n < line.length && (line[n] == 'x' || line[n] == 'X');
}

/// Skor relevansi sebuah baris terhadap nominal total.
///
/// Bonus: kata "total"/"amount due"/"jumlah" (+6), ada simbol/kode mata
/// uang (+2), angka berdesimal (+1). Penalti: "subtotal" (-4), baris
/// cash/tunai/kembali (-6), dan baris pajak berpersentase (-8).
double _scoreLine(String line, String raw) {
  final lower = line.toLowerCase();
  var score = 0.0;
  if (_totalRe.hasMatch(lower)) score += 6;
  if (_hasCurrencyMark(line)) score += 2;
  if (raw.contains('.') || raw.contains(',')) score += 1;
  if (lower.contains('subtotal') || lower.contains('sub total')) score -= 4;
  if (_cashRe.hasMatch(lower)) score -= 6;
  if (_taxRe.hasMatch(lower) && line.contains('%')) score -= 8;
  return score;
}

bool _hasCurrencyMark(String line) {
  if (line.contains('£') || line.contains(r'$') || line.contains('€')) {
    return true;
  }
  return RegExp(r'\b(GBP|USD|EUR|IDR|RP)\b', caseSensitive: false)
      .hasMatch(line);
}

/// Tebak kategori Away Day dari isi struk.
///
/// Urutan pemeriksaan penting: hotel lebih dulu, lalu transport, makanan,
/// merchandise, tiket, dan terakhir "lainnya". Makanan diperiksa sebelum
/// merchandise supaya kafe yang memakai kata "shop" (mis. "The Pie Shop")
/// tetap terklasifikasi sebagai makanan.
AwayDayCategory _detectCategory(String text) {
  final lower = text.toLowerCase();
  bool has(List<String> words) => words.any((w) => _hasWord(lower, w));

  if (has(['hotel', 'room', 'night', 'check-in', 'check in', 'booking'])) {
    return AwayDayCategory.hotel;
  }
  if (has([
    'train', 'rail', 'tube', 'tfl', 'oyster', 'bus', 'taxi', 'uber', //
    'grab', 'gojek', 'flight', 'airline', 'garuda', 'parking',
  ])) {
    return AwayDayCategory.transport;
  }
  // Makanan dicek sebelum merchandise supaya kafe yang juga memakai kata
  // "shop" (mis. "The Pie Shop") tetap terklasifikasi sebagai makanan.
  if (has([
    'restaurant', 'cafe', 'coffee', 'pizza', 'burger', 'pub', 'bar', //
    'meal', 'food', 'warung', 'nasi', 'resto',
  ])) {
    return AwayDayCategory.makanan;
  }
  if (has(['shop', 'store', 'kit', 'jersey', 'shirt', 'scarf', 'merch'])) {
    return AwayDayCategory.merchandise;
  }
  if (has(['ticket', 'admission'])) return AwayDayCategory.tiket;
  return AwayDayCategory.lainnya;
}

/// Susun judul draf.
///
/// Untuk tiket: "Tiket <klubA> vs <klubB>" (atau satu klub, atau label
/// kategori bila klub tidak terdeteksi). Untuk struk: baris pertama yang
/// punya minimal 3 huruf, dipotong 40 karakter dan dijadikan title case.
String _buildTitle(
  DocKind kind,
  String text,
  List<PlClub> found,
  AwayDayCategory category,
) {
  if (kind == DocKind.ticket) {
    if (found.length >= 2) {
      return 'Tiket ${found[0].shortName} vs ${found[1].shortName}';
    }
    if (found.length == 1) return 'Tiket ${found[0].shortName}';
    return _categoryLabel(category);
  }
  for (final raw in text.split('\n').take(4)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_letters.allMatches(line).length < 3) continue;
    final cut = line.length > 40 ? line.substring(0, 40) : line;
    return _titleCase(cut);
  }
  return _categoryLabel(category);
}

/// Ubah teks menjadi judul kapital per kata.
String _titleCase(String s) => s
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length == 1
        ? w.toUpperCase()
        : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

/// Label Indonesia untuk tiap kategori Away Day.
String _categoryLabel(AwayDayCategory c) => switch (c) {
      AwayDayCategory.tiket => 'Tiket',
      AwayDayCategory.hotel => 'Hotel',
      AwayDayCategory.transport => 'Transport',
      AwayDayCategory.merchandise => 'Merchandise',
      AwayDayCategory.makanan => 'Makanan',
      AwayDayCategory.lainnya => 'Lainnya',
    };

/// Cek rentang tanggal (bulan 1..12, hari 1..31).
bool _validDate(int day, int month) =>
    month >= 1 && month <= 12 && day >= 1 && day <= 31;

/// Cari tanggal di dalam teks OCR.
///
/// Pola yang dikenali berurutan: `dd/mm/yyyy`, `dd Mon yyyy` (bulan bahasa
/// Inggris, 3 huruf pertama), lalu `yyyy-mm-dd`. Tahun dua digit dianggap
/// abad 2000. Mengembalikan null bila tidak ada pola yang cocok atau
/// tanggalnya di luar rentang.
DateTime? _detectDate(String text) {
  final slash = RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{2,4})\b').firstMatch(text);
  if (slash != null) {
    final day = int.parse(slash.group(1)!);
    final month = int.parse(slash.group(2)!);
    var year = int.parse(slash.group(3)!);
    if (year < 100) year += 2000;
    if (_validDate(day, month)) return DateTime(year, month, day);
  }

  final worded =
      RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{2,4})\b').firstMatch(text);
  if (worded != null) {
    final month = _months[worded.group(2)!.toLowerCase().substring(0, 3)];
    final day = int.parse(worded.group(1)!);
    var year = int.parse(worded.group(3)!);
    if (year < 100) year += 2000;
    if (month != null && _validDate(day, month)) {
      return DateTime(year, month, day);
    }
  }

  final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
  if (iso != null) {
    final year = int.parse(iso.group(1)!);
    final month = int.parse(iso.group(2)!);
    final day = int.parse(iso.group(3)!);
    if (_validDate(day, month)) return DateTime(year, month, day);
  }
  return null;
}

/// Petakan tiket ke id laga yang relevan.
///
/// Hanya berlaku untuk dokumen tiket yang memuat dua klub. Bila tanggal
/// dokumen tersedia, dicari laga yang kickoff-nya dalam rentang +/-1 hari dari
/// tanggal itu; bila tidak, dipakai laga mendatang yang paling dekat.
int? _detectMatch(
  List<PlClub> found,
  List<FootballMatch> matches,
  DateTime? date,
  DocKind kind,
) {
  if (kind != DocKind.ticket || found.length < 2) return null;
  final a = found[0];
  final b = found[1];

  bool involves(FootballMatch m, PlClub c) =>
      c.isTeam(m.homeName, m.homeTla) || c.isTeam(m.awayName, m.awayTla);

  final candidates =
      matches.where((m) => involves(m, a) && involves(m, b)).toList();
  if (candidates.isEmpty) return null;

  if (date != null) {
    final target = DateTime.utc(date.year, date.month, date.day);
    final within = candidates.where((m) {
      final k = m.kickoffUtc.toUtc();
      final kickoffDay = DateTime.utc(k.year, k.month, k.day);
      return kickoffDay.difference(target).inDays.abs() <= 1;
    }).toList()
      ..sort((x, y) => x.kickoffUtc.compareTo(y.kickoffUtc));
    return within.isEmpty ? null : within.first.id;
  }

  final now = DateTime.now().toUtc();
  final upcoming = candidates
      .where((m) => m.kickoffUtc.toUtc().isAfter(now))
      .toList()
    ..sort((x, y) => x.kickoffUtc.compareTo(y.kickoffUtc));
  return upcoming.isEmpty ? null : upcoming.first.id;
}
