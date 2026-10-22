import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR on-device (Google ML Kit) - tidak butuh internet / API key.
///
/// Alur Lens: [recognize] mengembalikan teks mentah -> `parseReceipt` menyusun
/// `ReceiptDraft` -> `lens_provider` -> UI. Lihat `docs/feature-map.md`
/// (bagian lens).
class LensRepository {
  /// Jalankan OCR Latin pada gambar di [imagePath] dan kembalikan seluruh teks.
  ///
  /// Recognizer dibuka lalu ditutup di `finally` supaya sumber daya native
  /// tidak bocor. Tidak ada I/O jaringan maupun penyimpanan.
  Future<String> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return result.text;
    } finally {
      await recognizer.close();
    }
  }
}

/// Penyedia [LensRepository] tunggal.
final lensRepositoryProvider = Provider((ref) => LensRepository());
