import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// Hasil rute jalan dari OSRM: titik-titik polyline, jarak, dan lama tempuh.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });

  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;
}

/// Parse respons OSRM (`routes[0]`, geometri GeoJSON).
///
/// `geometry.coordinates` berpasangan `[lng, lat]` (urutan GeoJSON),
/// dibalik menjadi [LatLng] (lat, lng). Mengembalikan null untuk respons
/// yang bukan `code: Ok`, rute kosong, atau JSON yang rusak — tidak pernah
/// melempar exception.
RouteResult? parseOsrmRoute(Map<String, dynamic> json) {
  try {
    if (json['code'] != 'Ok') return null;
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final first = routes.first;
    if (first is! Map) return null;
    final geometry = first['geometry'];
    if (geometry is! Map) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return null;

    final points = <LatLng>[];
    for (final c in coordinates) {
      if (c is! List || c.length < 2) return null;
      final lng = c[0];
      final lat = c[1];
      if (lng is! num || lat is! num) return null;
      points.add(LatLng(lat.toDouble(), lng.toDouble()));
    }

    final distance = first['distance'];
    final duration = first['duration'];
    if (distance is! num || duration is! num) return null;

    return RouteResult(
      points: points,
      distanceKm: distance.toDouble() / 1000,
      durationMin: duration.toDouble() / 60,
    );
  } catch (_) {
    return null;
  }
}

/// Repository rute jalan memakai OSRM publik (tanpa API key).
///
/// Selalu mengembalikan null (bukan throw) saat gagal: timeout, DNS,
/// server error, atau respons tidak sesuai schema.
class RouteRepository {
  RouteRepository(this._dio);

  final Dio _dio;

  static const _endpoint = 'https://router.project-osrm.org/route/v1/driving';

  Future<RouteResult?> fetch(LatLng from, LatLng to) async {
    final url = '$_endpoint/${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson';
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: {
            'User-Agent': 'ultimate_fanzone/1.1 (Flutter; stadium-pointer)',
          },
        ),
      );
      final data = response.data;
      if (data == null) return null;
      return parseOsrmRoute(data);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
