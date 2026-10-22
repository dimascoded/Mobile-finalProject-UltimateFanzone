import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../data/notification_service.dart';

/// Berapa lama menunggu fix GPS sebelum menyerah.
const sosLocationTimeout = Duration(seconds: 12);

/// Alur tombol SOS: baca GPS -> tampilkan koordinat + notifikasi lokal.
///
/// BATASAN PENTING: aplikasi TIDAK punya backend pengirim. Tidak ada pesan yang
/// dikirim ke siapa pun; koordinat hanya tampil di perangkat ini. Lihat
/// `docs/feature-map.md` (bagian sos_emergency).
class SosNotifier extends StateNotifier<AsyncValue<String?>> {
  SosNotifier() : super(const AsyncData(null));

  /// Minta izin lokasi, ambil posisi, lalu kembalikan teks berisi koordinat.
  ///
  /// Mengubah state menjadi [AsyncData] berisi pesan (bukan null) saat berhasil,
  /// atau [AsyncError] dengan pesan Indonesia saat gagal. `mounted` diperiksa
  /// sebelum menulis state akhir.
  Future<void> trigger() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(
            'Lokasi GPS belum aktif. Nyalakan lokasi perangkat lalu coba lagi.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Izin lokasi ditolak, koordinat tidak bisa dibaca.');
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: sosLocationTimeout,
      );
      final koordinat = '${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}';

      // PENTING: aplikasi ini tidak punya backend pengirim. Yang dilakukan
      // hanya menampilkan koordinat di perangkat ini + notifikasi lokal.
      // Jangan menulis "terkirim" karena tidak ada yang dikirim.
      await NotificationService.show(
          'SOS Darurat - Lokasi Tertangkap', koordinat);
      return 'Lokasi Anda: $koordinat\n'
          'Koordinat ini baru ditampilkan di perangkat ini dan BELUM '
          'dikirim ke siapa pun. Gunakan telepon layanan darurat 999/112 '
          'untuk melaporkan situasi.';
    });
    if (!mounted) return;
    state = result;
  }
}

/// Status SOS terkini: null (belum ditekan), loading, atau teks koordinat/galat.
final sosProvider = StateNotifierProvider<SosNotifier, AsyncValue<String?>>(
    (ref) => SosNotifier());
