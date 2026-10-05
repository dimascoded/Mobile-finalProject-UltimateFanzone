import 'dart:convert';

/// Baca klaim `exp` dari JWT tanpa memverifikasi signature.
///
/// Sisi klien tidak punya rahasia, jadi signature tidak bisa diperiksa di sini.
/// Yang diambil hanya waktu kedaluwarsa yang sudah ditandatangani server, agar
/// app tidak mengklaim sesi masih hidup padahal server sudah menolaknya (U5).
///
/// Mengembalikan null kalau token bukan JWT tiga bagian, `exp` tidak ada, atau
/// nilainya bukan angka.
DateTime? tokenExpiry(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
  } catch (_) {
    // Token rusak atau bukan base64 yang valid: perlakukan sebagai tanpa `exp`.
    return null;
  }
}
