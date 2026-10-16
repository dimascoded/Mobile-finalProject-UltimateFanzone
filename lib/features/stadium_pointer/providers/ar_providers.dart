import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/dio_client.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/route_repository.dart';

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

/// Mode uji: menyala = layar kompas memakai posisi sintetis di sekitar
/// stadion supaya rute jalan bisa dicoba tanpa berada di sana.
final demoNearStadiumProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Posisi yang dipakai layar kompas (peta, jarak, bearing, rute).
///
/// Saat [demoNearStadiumProvider] menyala dan stadion sudah dipilih,
/// mengembalikan posisi sintetis 0,012° ke selatan dan 0,010° ke barat
/// stadion (~1,5 km). Selain itu meneruskan [positionProvider] apa adanya.
///
/// Provider lain (stamp/passport) tetap membaca [positionProvider]
/// langsung dan tidak terpengaruh posisi simulasi ini.
final effectivePositionProvider =
    Provider.autoDispose<AsyncValue<Position>>((ref) {
  final demo = ref.watch(demoNearStadiumProvider);
  final stadium = ref.watch(selectedStadiumProvider);
  if (demo && stadium != null) {
    return AsyncValue.data(Position(
      latitude: stadium.lat - 0.012,
      longitude: stadium.lng - 0.010,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
  }
  return ref.watch(positionProvider);
});

typedef RouteQuery = ({
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
});

final routeRepositoryProvider = Provider<RouteRepository>(
  (ref) => RouteRepository(ref.watch(dioProvider)),
);

/// Rute jalan OSRM dari posisi ke stadion.
///
/// Pembulatan fromLat/fromLng ke 3 desimal (~111 m) dilakukan di layar
/// sebelum key dibangun, supaya jitter GPS tidak fetch ulang tiap update.
final routeProvider =
    FutureProvider.autoDispose.family<RouteResult?, RouteQuery>(
  (ref, q) => ref.watch(routeRepositoryProvider).fetch(
        LatLng(q.fromLat, q.fromLng),
        LatLng(q.toLat, q.toLng),
      ),
);

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
