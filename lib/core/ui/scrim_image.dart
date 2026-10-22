import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'pitch_pattern.dart';

/// Gambar header dengan scrim gelap bertingkat di bagian bawah.
///
/// Lapisan scrim memastikan teks di atas gambar tetap terbaca apa pun latar
/// fotonya, dan bila aset gagal dimuat otomatis digantikan gradien warna dari
/// [FanzoneColors]. Dipakai untuk header layar auth (login, register,
/// kunci), hero beranda, dan header tiap fitur.
///
/// Path aset berasal dari `AppImages` di `app_images.dart`.
class ScrimImage extends StatelessWidget {
  const ScrimImage({
    super.key,
    required this.assetPath,
    this.child,
    this.height,
    this.borderRadius = AppRadius.lg,
    this.fallbackColors,
    this.scrim = 0.6,
    this.showPitchPattern = false,
  });

  /// Path aset gambar, misalnya `AppImages.heroMalamLaga`.
  final String assetPath;

  /// Konten yang diletakkan di atas gambar (biasanya teks atau tombol).
  final Widget? child;

  /// Tinggi tetap gambar; bila null tinggi mengikuti parent.
  final double? height;

  /// Radius sudut gambar, default [AppRadius.lg].
  final double borderRadius;

  /// Warna gradien pengganti saat aset gagal dimuat; default memakai
  /// `heroGradientStart` dan `heroGradientEnd`.
  final List<Color>? fallbackColors;

  /// Kekuatan scrim hitam di bagian bawah, 0.0 sampai 1.0.
  final double scrim;

  /// Tampilkan [PitchPattern] di atas gambar sebagai ornamen lapangan.
  final bool showPitchPattern;

  @override
  Widget build(BuildContext context) {
    final fz = context.fz;
    final fallback = fallbackColors ??
        [
          fz.heroGradientStart,
          fz.heroGradientEnd,
        ];
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final width = MediaQuery.of(context).size.width;

    final image = Image.asset(
      assetPath,
      fit: BoxFit.cover,
      cacheWidth: (width * devicePixelRatio).round(),
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fallback,
            ),
          ),
        );
      },
    );

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        image,
        // Bottom-heavy scrim
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0),
                Colors.black.withValues(alpha: scrim),
              ],
            ),
          ),
        ),
        if (showPitchPattern) const PitchPattern(),
        if (child != null) child!,
      ],
    );

    if (height != null) {
      content = SizedBox(height: height, child: content);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: content,
    );
  }
}
