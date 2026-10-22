import 'package:flutter/material.dart';

// STRUKTUR UI — ClubCrest
// Ukuran: SizedBox ukuran logo + Image.network; tanpa Scaffold.
// [1] Crest jaringan  — gambar logo klub dari crestUrl, fallback ke _Badge
//                        saat URL kosong, gagal dimuat, atau frame belum siap
// [2] _Badge          — lingkaran warna klub berisi kode TLA, ukuran teks
//                        mengikuti ukuran logo
// Tabel/kolom: tanpa tabel; satu logo bundar.
// Sumber data: tanpa provider; crestUrl, tla, color, dan size dari parameter.
/// Logo klub: menampilkan crest dari [crestUrl]; bila URL kosong atau gagal
/// dimuat (offline / data contoh) otomatis jatuh ke badge warna + [tla].
class ClubCrest extends StatelessWidget {
  const ClubCrest({
    super.key,
    required this.crestUrl,
    required this.tla,
    this.color,
    this.size = 40,
  });

  final String? crestUrl;
  final String tla;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = crestUrl;
    final fallback = _Badge(color: color, tla: tla, size: size);
    if (url == null || url.isEmpty) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? child : fallback,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.tla, required this.size});

  final Color? color;
  final String tla;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.surfaceContainerHighest;
    final fg = color == null
        ? scheme.onSurface
        : ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        tla,
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}
