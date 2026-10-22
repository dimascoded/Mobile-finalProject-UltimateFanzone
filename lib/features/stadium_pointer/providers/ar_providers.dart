import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/network/dio_client.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/route_repository.dart';

/// Pilihan manual stadion untuk AR Pointer.
///
/// `null` berarti mengikuti klub favorit (default UI5). Bila di-set, layar
/// memakai klub pada indeks tersebut (dikunci ke rentang daftar klub).
/// `autoDispose`: hanya relevan saat berada di layar Stadium Pointer.
///
/// Tanpa efek samping; state UI lokal.
final selectedStadiumIndexProvider =
    StateProvider.autoDispose<int?>((ref) => null);

/// Stadion aktif untuk kompas/AR.
///
/// Logika pemilihan (urutan prioritas):
/// 1. Indeks manual dari [selectedStadiumIndexProvider] bila terisi.
/// 2. Klab favorit dari [favoriteClubProvider] bila cocok di [clubsProvider].
/// 3. Klub pertama di daftar sebagai fallback.
///
/// Default UI5: mengikuti klub favorit, bukan klub pertama.
/// `autoDispose`: hanya dipakai layar Pointer.
///
/// Provider turunan dari [clubsProvider] dan [favoriteClubProvider]; tanpa efek
/// samping.
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

/// Stream posisi perangkat via GPS.
///
/// Meminta izin lokasi bila belum diberi; melempar `Exception('Izin lokasi ditolak')`
/// bila izin ditolak permanen atau pengguna menolak. Menggunakan
/// [LocationAccuracy.high] dengan `distanceFilter: 2` meter.
///
/// `autoDispose`: stream dihentikan saat tidak ada yang menonton layar.
/// Efek samping: izin lokasi, akses sensor GPS (hardware).
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

/// Stream arah kompas (heading derajat 0-359, Utara 0).
///
/// Hanya meneruskan event dengan [FlutterCompassEvent.heading] tidak null.
/// Melempar error bila [FlutterCompass.events] null (sensor kompas tidak
/// tersedia di perangkat).
///
/// `autoDispose`: berhenti saat layar tidak aktif. Efek samping: akses
/// sensor magnetometer/kompas (hardware).
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
///
/// `autoDispose`: bersifat lokal layar debug/demo. Tanpa efek samping.
final demoNearStadiumProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Posisi yang dipakai layar kompas (peta, jarak, bearing, rute).
///
/// Saat [demoNearStadiumProvider] menyala dan stadion sudah dipilih,
/// mengembalikan posisi sintetis 0,012° ke selatan dan 0,010° ke barat
/// stadion (~1,5 km). Selain itu meneruskan [positionProvider] apa adanya.
///
/// Provider lain (stamp/passport) tetap membaca [positionProvider]
/// langsung dan tidak terpengaruh posisi simulasi ini.
///
/// `autoDispose`: menurunkan beban stream bila layar ditutup.
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

/// Parameter rute: titik asal dan titik tujuan dalam koordinat desimal.
///
/// Bentuknya `record` (bukan class) supaya bisa dipakai sebagai key
/// `family` pada [routeProvider] tanpa objek khusus.
typedef RouteQuery = ({
  double fromLat,
  double fromLng,
  double toLat,
  double toLng,
});

/// Repository rute jalan (OSRM) yang dipakai [routeProvider].
///
/// Dibuat sekali dan dipakai bersama; tanpa efek samping selain pembuatan
/// instance [RouteRepository].
final routeRepositoryProvider = Provider<RouteRepository>(
  (ref) => RouteRepository(ref.watch(dioProvider)),
);

/// Rute jalan OSRM dari posisi ke stadion.
///
/// Parameter [RouteQuery] dibulatkan ke 3 desimal (~111 m) di sisi UI
/// sebelum key dibangun supaya jitter GPS tidak memicu fetch ulang tiap
/// pembaruan posisi.
///
/// `autoDispose.family`: cache per query rute; dibersihkan saat layar ditutup.
/// Efek samping: HTTP ke OSRM melalui [RouteRepository].
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

/// Informasi pointer ke stadion: jarak dan bearing.
///
/// [distanceKm] dalam kilometer (Geolocator.distanceBetween dibagi 1000),
/// [bearing] dinormalisasi ke 0-359. Fungsi murni, tanpa efek samping.
class PointerInfo {
  const PointerInfo(this.distanceKm, this.bearing);
  final double distanceKm, bearing;
}

/// Hitung jarak (km) dan bearing (0-359) dari posisi ke klub/stadion.
///
/// Fungsi murni, tanpa efek samping.
PointerInfo computePointer(Position p, PlClub c) {
  final d =
      Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lng) / 1000;
  final b = Geolocator.bearingBetween(p.latitude, p.longitude, c.lat, c.lng);
  return PointerInfo(d, (b + 360) % 360);
}
