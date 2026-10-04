import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';

final selectedStadiumIndexProvider = StateProvider.autoDispose<int>((ref) => 0);

final selectedStadiumProvider = Provider.autoDispose<PlClub?>((ref) {
  final clubs = ref.watch(clubsProvider).valueOrNull;
  if (clubs == null || clubs.isEmpty) return null;
  final i = ref.watch(selectedStadiumIndexProvider);
  return clubs[i.clamp(0, clubs.length - 1)];
});

final positionProvider = StreamProvider.autoDispose<Position>((ref) async* {
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw Exception('Izin lokasi ditolak');
  }
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
  );
});

final compassProvider = StreamProvider.autoDispose<double>((ref) {
  final events = FlutterCompass.events;
  if (events == null) return Stream.error(Exception('Sensor kompas tidak tersedia'));
  return events.where((e) => e.heading != null).map((e) => (e.heading! + 360) % 360);
});

final accelerometerProvider = StreamProvider.autoDispose<AccelerometerEvent>((ref) => accelerometerEventStream());
final gyroscopeProvider = StreamProvider.autoDispose<GyroscopeEvent>((ref) => gyroscopeEventStream());

class PointerInfo {
  const PointerInfo(this.distanceKm, this.bearing);
  final double distanceKm, bearing;
}

PointerInfo computePointer(Position p, PlClub c) {
  final d = Geolocator.distanceBetween(p.latitude, p.longitude, c.lat, c.lng) / 1000;
  final b = Geolocator.bearingBetween(p.latitude, p.longitude, c.lat, c.lng);
  return PointerInfo(d, (b + 360) % 360);
}