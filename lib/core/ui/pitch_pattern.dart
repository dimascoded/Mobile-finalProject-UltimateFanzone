import 'package:flutter/material.dart';

/// Pola garis lapangan yang digambar tipis di atas gambar header.
///
/// Lapisan dekoratif tanpa interaksi: dipakai [ScrimImage] lewat parameter
/// `showPitchPattern` untuk memberi kesan lapangan pada header pertandingan
/// seperti layar login, beranda, dan header fitur.
class PitchPattern extends StatelessWidget {
  const PitchPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _PitchPainter(),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Melukis garis lapangan (garis tengah, lingkaran tengah, area penalti) dengan
/// warna putih transparan tipis.
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Halfway line
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);

    // Centre circle
    final radius = size.width * 0.08;
    canvas.drawCircle(Offset(centerX, centerY), radius, paint);

    // Penalty box - one penalty box (on bottom half near edge area)
    final boxWidth = size.width * 0.4;
    final boxHeight = size.height * 0.25;
    final boxLeft = centerX - boxWidth / 2;
    final boxTop = size.height - boxHeight; // bottom penalty area
    canvas.drawRect(Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
