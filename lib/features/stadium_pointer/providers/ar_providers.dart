import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';

/// null = belum ada pilihan manual, jadi mengikuti klub favorit.
final selectedStadiumIndexProvider =
    StateProvider.autoDispose<int?>((ref) => null);

final selectedStadiumProvider = Provider.autoDispose<PlClub?>((ref) {
  final clubs = ref.watch(clubsProvider).valueOrNull;
  if (clubs == null || clubs.isEmpty) return null;
  final fav = ref.watch(favoriteClubProvider);
  // UI5: default-nya stadion tim favorit, bukan klub pertama di daftar JSON.
  final chosen = ref.watch(selectedStadiumIndexProvider);
  if (chosen != null) return clubs[chosen.clamp(0, clubs.length - 1)];
  if (fav != null) {
    final i = clubs.indexWhere((c) => c.key == fav.key);
    if (i >= 0) return clubs[i];
  }
  return clubs.first;
});

final positionProvider = StreamProvider.autoDispose<Position>((ref) async* {
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    throw Exception('Izin lokasi ditolak');
  }
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 2),
  );
});

final compassProvider = StreamProvider.autoDispose<double>((ref) {
  final events = FlutterCompass.events;
  if (events == null) {
    return Stream.error(Exception('Sensor kompas tidak tersedia'));
  }
  return events
      .where((e) => e.heading != null)
      .map((e) => (e.heading! + 360) % 360);
});

// Catatan (UI5): accelerometerProvider/gyroscopeProvider yang pernah ada di sini
// dihapus karena tidak ada layar yang membacanya. Membukanya lewat
// StreamProvider berarti sensor tetap aktif selama ada yang menonton,
// memboroskan baterai tanpa manfaat. Data accelerometer yang berguna
// (ayunan HP untuk penalty) sudah punya provider sendiri di
// features/penalty_shootout/providers/shake_provider.dart.

class PointerInfo {
  const PointerInfo(this.distanceKm, this.bearing);
  final double distanceKm, bearing;
}

PointerInfo computePointer(Position p, PlClub c) {
  final d =
      Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lng) / 1000;
  final b = Geolocator.bearingBetween(p.latitude, p.longitude, c.lat, c.lng);
  return PointerInfo(d, (b + 360) % 360);
}
