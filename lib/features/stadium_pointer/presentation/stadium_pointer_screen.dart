import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/data/models.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../providers/ar_providers.dart';

// STRUKTUR UI — StadiumPointerScreen
// Ukuran: Scaffold + AppBar, body clubs.when (loading/error/data) dibungkus
// PermissionGate, tanpa batas lebar; _Picker memakai Column, _Pointer memakai
// SingleChildScrollView
// [1] Pemilih stadion — DropdownButtonFormField klub (crest + nama stadion) di atas
// [2] _Pointer — isi layar: _LocationMap, catatan rute, kartu info rute, switch mode demo
// [3] _CompassDial — dial kompas custom (_DialPainter) berisi sudut relatif ke stadion
// [4] Identitas klub — crest, nama klub, stadion, kota
// [5] Kartu informasi — 3 baris ListTile: jarak ke stadion, azimut + heading HP, arah relatif
// [6] Aksi — tombol buka Google Maps, catatan sensor, tombol muat ulang lokasi
// Tabel/kolom: tanpa tabel; kartu informasi 3 baris ListTile satu kolom
// Sumber data: clubsProvider, selectedStadiumProvider, effectivePositionProvider,
// compassProvider, clubCrestProvider, demoNearStadiumProvider, routeProvider,
// positionProvider, selectedStadiumIndexProvider

/// Kompas arah ke stadion klub favorit.
///
/// Panah = bearing(stadion) - heading(HP), jadi 0° = lurus ke depan.
/// Memakai magnetometer (flutter_compass) + GPS (geolocator).
class StadiumPointerScreen extends ConsumerWidget {
  const StadiumPointerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kompas Stadion')),
      body: clubs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.sports_soccer,
          title: 'Gagal memuat klub',
          message: '$e',
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.sports_soccer,
              title: 'Data klub kosong',
              message: 'assets/data/pl_clubs.json tidak berisi klub.',
            );
          }
          return PermissionGate(
            permissionKey: 'location',
            icon: Icons.explore,
            title: 'Arah ke stadion perlu lokasi',
            message:
                'Aplikasi memakai GPS untuk menghitung jarak dan magnetometer HP '
                'sebagai kompas. Tidak ada data yang dikirim ke server.',
            child: _Picker(clubs: list),
          );
        },
      ),
    );
  }
}

class _Picker extends ConsumerWidget {
  const _Picker({required this.clubs});

  final List<PlClub> clubs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(selectedStadiumProvider);
    final position = ref.watch(effectivePositionProvider);
    final heading = ref.watch(compassProvider);
    final crests = ref.watch(clubCrestProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: DropdownButtonFormField<PlClub>(
            key: ValueKey(target?.key),
            initialValue: target,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Stadion',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.stadium),
            ),
            items: [
              for (final c in clubs)
                DropdownMenuItem<PlClub>(
                  value: c,
                  child: Row(children: [
                    ClubCrest(
                      crestUrl: crests[c.tla.toUpperCase()],
                      tla: c.tla,
                      color: c.colorValue,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${c.name} - ${c.stadium}',
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              ref.read(selectedStadiumIndexProvider.notifier).state =
                  clubs.indexOf(v);
            },
          ),
        ),
        Expanded(
          child: _Pointer(
            target: target,
            crestUrl: target == null ? null : crests[target.tla.toUpperCase()],
            position: position,
            heading: heading,
            onRefresh: () {
              ref.invalidate(positionProvider);
              ref.invalidate(compassProvider);
            },
          ),
        ),
      ],
    );
  }
}

class _Pointer extends ConsumerWidget {
  const _Pointer({
    required this.target,
    required this.crestUrl,
    required this.position,
    required this.heading,
    required this.onRefresh,
  });

  final PlClub? target;
  final String? crestUrl;
  final AsyncValue<Position> position;
  final AsyncValue<double> heading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (target == null) {
      return const EmptyState(
        icon: Icons.touch_app,
        title: 'Pilih stadion',
        message: 'Pilih klub di atas untuk melihat arah ke stadionnya.',
      );
    }
    final club = target!;

    if (position.hasError) {
      return EmptyState(
        icon: Icons.location_disabled,
        title: 'Lokasi tidak tersedia',
        message: '${position.error}',
      );
    }
    if (heading.hasError) {
      return const EmptyState(
        icon: Icons.explore_off,
        title: 'Kompas tidak tersedia',
        message: 'Perangkat ini tidak punya sensor magnetometer. '
            'Uji di HP fisik, bukan emulator.',
      );
    }
    if (!position.hasValue || !heading.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final pos = position.requireValue;
    final info = computePointer(pos, club);
    final hdg = heading.requireValue;
    //bearing - heading, dinormalisasi ke 0..360 (0 = lurus ke depan)
    final relative = (info.bearing - hdg + 360) % 360;

    final demo = ref.watch(demoNearStadiumProvider);
    // Bulatkan posisi ke 3 desimal dulu supaya jitter GPS tidak
    // membangun family key (dan fetch rute) baru tiap update.
    final routeAsync = ref.watch(routeProvider((
      fromLat: _round3(pos.latitude),
      fromLng: _round3(pos.longitude),
      toLat: club.lat,
      toLng: club.lng,
    )));
    final route = routeAsync.valueOrNull;
    final routeUnavailable = routeAsync.hasValue && route == null;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        children: [
          _LocationMap(
            position: pos,
            target: club,
            routePoints: route?.points,
            routeUnavailable: routeUnavailable,
            showDemoChip: demo,
          ),
          if (routeUnavailable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Rute jalan tidak tersedia dari lokasimu (mungkin terpisah '
                'laut atau terlalu jauh). Garis putus-putus menunjukkan '
                'arah lurus.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (routeAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (route != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Rute berkendara: '
                        '${route.distanceKm.toStringAsFixed(1)} km, '
                        'sekitar ${_durationLabel(route.durationMin)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SwitchListTile(
            value: demo,
            onChanged: (v) =>
                ref.read(demoNearStadiumProvider.notifier).state = v,
            title: const Text('Uji rute dengan lokasi simulasi'),
            subtitle: const Text(
              'Memakai posisi sekitar 1,5 km dari stadion supaya rute '
              'bisa dicoba tanpa berada di sana.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 4),
          _CompassDial(relativeBearing: relative, color: club.colorValue),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ClubCrest(
              crestUrl: crestUrl,
              tla: club.tla,
              color: club.colorValue,
              size: 28,
            ),
            const SizedBox(width: 8),
            Text(club.name, style: Theme.of(context).textTheme.titleLarge),
          ]),
          Text(club.stadium, style: Theme.of(context).textTheme.bodyMedium),
          Text(club.city, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.straighten),
                  title: Text('${info.distanceKm.toStringAsFixed(2)} km'),
                  subtitle: const Text('jarak Anda ke stadion'),
                ),
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title:
                      Text('${info.bearing.toStringAsFixed(0)}\u00B0 azimut'),
                  subtitle: Text('heading HP ${hdg.toStringAsFixed(0)}\u00B0'),
                ),
                ListTile(
                  leading: Icon(
                    relative < 45 || relative > 315
                        ? Icons.check_circle
                        : Icons.turn_right,
                    color:
                        relative < 45 || relative > 315 ? scheme.primary : null,
                  ),
                  title: Text(_relativeLabel(relative)),
                  subtitle:
                      Text('selisih ${relative.toStringAsFixed(0)}\u00B0'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _openInGoogleMaps(context, club),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Buka di Google Maps'),
          ),
          const SizedBox(height: 12),
          Text(
            'Sensor: magnetometer (kompas) + GPS.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Muat ulang lokasi'),
          ),
        ],
      ),
    );
  }

  static String _relativeLabel(double deg) {
    if (deg < 22.5 || deg >= 337.5) return 'Lurus ke depan';
    if (deg < 67.5) return 'Sedikit ke kanan';
    if (deg < 112.5) return 'Ke kanan';
    if (deg < 157.5) return 'Tajam ke kanan';
    if (deg < 202.5) return 'Belakang';
    if (deg < 247.5) return 'Tajam ke kiri';
    if (deg < 292.5) return 'Ke kiri';
    return 'Sedikit ke kiri';
  }
}

/// Bulatkan ke 3 desimal (~111 m) untuk family key rute.
double _round3(double v) => double.parse(v.toStringAsFixed(3));

String _durationLabel(double minutes) {
  final m = minutes.round();
  if (m < 60) return '$m menit';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '$h jam' : '$h jam $rest menit';
}

Future<void> _openInGoogleMaps(BuildContext context, PlClub club) async {
  // Asal sengaja tidak dikirim: Google Maps memakai lokasi GPS asli.
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=${club.lat},${club.lng}'
    '&travelmode=driving',
  );
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showMapsError(context);
    }
  } catch (_) {
    if (context.mounted) {
      _showMapsError(context);
    }
  }
}

void _showMapsError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Tidak bisa membuka aplikasi peta.')),
  );
}

class _LocationMap extends StatefulWidget {
  const _LocationMap({
    required this.position,
    required this.target,
    this.routePoints,
    this.routeUnavailable = false,
    this.showDemoChip = false,
  });

  final Position position;
  final PlClub target;

  /// Titik-titik rute jalan OSRM; null = belum ada / tidak tersedia.
  final List<LatLng>? routePoints;

  /// true = rute sudah selesai diambil dan hasilnya null (garis putus-putus).
  final bool routeUnavailable;

  /// true = tampilkan chip "Lokasi simulasi" di pojok kiri atas.
  final bool showDemoChip;

  @override
  State<_LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<_LocationMap> {
  final _mapController = MapController();

  LatLng get _deviceLocation =>
      LatLng(widget.position.latitude, widget.position.longitude);

  LatLng get _stadiumLocation => LatLng(widget.target.lat, widget.target.lng);

  void _fitAllPoints() {
    final points = <LatLng>[
      _deviceLocation,
      _stadiumLocation,
      ...?widget.routePoints,
    ];
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(36),
        maxZoom: 15,
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fit hanya saat rute baru datang atau stadion berganti, bukan tiap
    // update GPS (instance [RouteResult]-nya sama selama tidak berubah).
    final stadiumChanged = widget.target.key != oldWidget.target.key;
    final routeChanged = !identical(widget.routePoints, oldWidget.routePoints);
    if (stadiumChanged || routeChanged) {
      _fitAllPoints();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubColor = widget.target.colorValue;
    final routePoints = widget.routePoints;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        height: 280,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _deviceLocation,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ultimate_fanzone',
                ),
                if (routePoints != null && routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      // Border putih 2px di bawah garis biru.
                      Polyline(
                        points: routePoints,
                        strokeWidth: 9,
                        color: Colors.white,
                      ),
                      Polyline(
                        points: routePoints,
                        strokeWidth: 5,
                        color: scheme.primary,
                      ),
                    ],
                  )
                else if (widget.routeUnavailable)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_deviceLocation, _stadiumLocation],
                        strokeWidth: 3,
                        color: scheme.outline,
                        pattern: StrokePattern.dashed(
                          segments: const [8, 6],
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _deviceLocation,
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.my_location,
                        color: scheme.primary,
                        size: 34,
                      ),
                    ),
                    Marker(
                      point: _stadiumLocation,
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.stadium,
                        color: clubColor,
                        size: 36,
                      ),
                    ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            if (widget.showDemoChip)
              Positioned(
                top: 8,
                left: 8,
                child: Chip(
                  avatar: const Icon(Icons.science, size: 16),
                  label: const Text('Lokasi simulasi'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: Column(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Lokasi saya',
                      onPressed: () => _mapController.move(_deviceLocation, 14),
                      icon: const Icon(Icons.my_location),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Tampilkan lokasi dan stadion',
                      onPressed: _fitAllPoints,
                      icon: const Icon(Icons.zoom_out_map),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location, color: scheme.primary, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      const Text('Anda'),
                      const SizedBox(width: AppSpacing.md),
                      Icon(Icons.stadium, color: clubColor, size: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(widget.target.shortName),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassDial extends StatelessWidget {
  const _CompassDial({required this.relativeBearing, required this.color});

  final double relativeBearing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = math.min(constraints.maxWidth * 0.6, 190.0);
        return Center(
          child: SizedBox(
            key: const ValueKey('stadium-compass-dial'),
            width: diameter,
            height: diameter,
            child: CustomPaint(
              painter: _DialPainter(
                relativeBearing: relativeBearing,
                color: color,
                diameter: diameter,
                tickColor: Theme.of(context).colorScheme.outline,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation, size: diameter * 0.22, color: color),
                    Text(
                      '${relativeBearing.toStringAsFixed(0)}\u00B0',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wrapper publik agar [_CompassDial] bisa di-pump dari widget test.
@visibleForTesting
class CompassDialTestWrapper extends StatelessWidget {
  const CompassDialTestWrapper({
    super.key,
    required this.relativeBearing,
    required this.color,
  });

  final double relativeBearing;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      _CompassDial(relativeBearing: relativeBearing, color: color);
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.relativeBearing,
    required this.color,
    required this.diameter,
    required this.tickColor,
  });

  final double relativeBearing;
  final Color color;
  final double diameter;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final scale = diameter / 240;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withAlpha(120),
    );

    // Tick tiap 45 derajat; tick utara lebih tebal. Panjang tick diskalakan.
    for (var deg = 0; deg < 360; deg += 45) {
      final a = (deg - 90) * math.pi / 180;
      final outer = center + Offset(math.cos(a), math.sin(a)) * (radius - 2);
      final inner = center +
          Offset(math.cos(a), math.sin(a)) *
              (radius - (deg % 90 == 0 ? 18 * scale : 10 * scale));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = deg % 90 == 0 ? color : tickColor
          ..strokeWidth = deg % 90 == 0 ? 3 : 1.5,
      );
    }

    // Jarum: 0 = utara layar. bearing relatif = 0 berarti stadion tepat di depan (utara).
    final angle = (relativeBearing - 90) * math.pi / 180;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * (radius - 26 * scale),
      Paint()
        ..color = color
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.relativeBearing != relativeBearing ||
      old.color != color ||
      old.diameter != diameter ||
      old.tickColor != tickColor;
}
