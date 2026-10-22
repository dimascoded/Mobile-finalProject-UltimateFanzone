import '../../away_day/providers/away_day_providers.dart';

/// Ubah nominal asing hasil pindai menjadi tiga nilai yang dipakai Away Day:
/// nominal asli, nilai Rupiah, dan padanan poundsterling.
///
/// Aturan:
/// - [amountForeign] harus > 0, kalau tidak hasilnya null.
/// - Kurs dari [rates] dipakai lebih dulu lewat [foreignToIdr]. Bila kurs
///   hilang untuk mata uang non-IDR, [manualIdr] dipakai asalkan > 0; kalau
///   tidak, hasilnya null supaya UI bisa meminta isian manual.
/// - [amountGbp] dihitung dari Rupiah lewat [idrToForeign] dan jatuh ke 0 bila
///   kurs GBP belum tersedia.
///
/// PENTING: kurs berbasis IDR (dari `https://api.exchangerate-api.com/v4/latest/IDR`),
/// jadi nominal asing ke Rupiah itu DIBAGI kurs, bukan dikali.
///
/// Mengembalikan null berarti data belum cukup untuk disimpan; pemanggil
/// harus meminta isian manual dari pengguna.
({double amountForeign, double amountIdr, double amountGbp})? toExpenseAmounts({
  required double amountForeign,
  required String currency,
  Map<String, double>? rates,
  double? manualIdr,
}) {
  if (amountForeign <= 0) return null;

  var idr = foreignToIdr(amountForeign, currency, rates);
  if (idr == null) {
    if (manualIdr != null && manualIdr > 0) {
      idr = manualIdr;
    } else {
      return null;
    }
  }

  return (
    amountForeign: amountForeign,
    amountIdr: idr,
    amountGbp: idrToForeign(idr, 'GBP', rates) ?? 0,
  );
}
