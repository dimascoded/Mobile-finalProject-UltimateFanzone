import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/data/models.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../providers/ar_providers.dart';

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
    final position = ref.watch(positionProvider);
    final heading = ref.watch(compassProvider);
    final crests = ref.watch(clubCrestProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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

class _Pointer extends StatelessWidget {
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
  Widget build(BuildContext context) {
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

    final info = computePointer(position.requireValue, club);
    final hdg = heading.requireValue;
    //bearing - heading, dinormalisasi ke 0..360 (0 = lurus ke depan)
    final relative = (info.bearing - hdg + 360) % 360;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _LocationMap(position: position.requireValue, target: club),
          const SizedBox(height: 16),
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
          Card(
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
                        relative < 45 || relative > 315 ? Colors.green : null,
                  ),
                  title: Text(_relativeLabel(relative)),
                  subtitle:
                      Text('selisih ${relative.toStringAsFixed(0)}\u00B0'),
                ),
              ],
            ),
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

class _LocationMap extends StatefulWidget {
  const _LocationMap({required this.position, required this.target});

  final Position position;
  final PlClub target;

  @override
  State<_LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<_LocationMap> {
  final _mapController = MapController();

  LatLng get _deviceLocation =>
      LatLng(widget.position.latitude, widget.position.longitude);

  LatLng get _stadiumLocation => LatLng(widget.target.lat, widget.target.lng);

  void _showBothLocations() {
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([_deviceLocation, _stadiumLocation]),
        padding: const EdgeInsets.all(36),
        maxZoom: 14,
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubColor = widget.target.colorValue;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
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
                  userAgentPackageName: 'smart_football_fan',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _deviceLocation,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
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
                      onPressed: _showBothLocations,
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
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location,
                          color: Colors.blue, size: 16),
                      const SizedBox(width: 4),
                      const Text('Anda'),
                      const SizedBox(width: 12),
                      Icon(Icons.stadium, color: clubColor, size: 16),
                      const SizedBox(width: 4),
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
    return SizedBox(
      width: 240,
      height: 240,
      child: CustomPaint(
        painter: _DialPainter(relativeBearing: relativeBearing, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.navigation, size: 52, color: color),
              Text(
                '${relativeBearing.toStringAsFixed(0)}\u00B0',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.relativeBearing, required this.color});

  final double relativeBearing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withAlpha(120),
    );

    // Tick tiap 45 derajat; tick utara lebih tebal.
    for (var deg = 0; deg < 360; deg += 45) {
      final a = (deg - 90) * math.pi / 180;
      final outer = center + Offset(math.cos(a), math.sin(a)) * (radius - 2);
      final inner = center +
          Offset(math.cos(a), math.sin(a)) *
              (radius - (deg % 90 == 0 ? 18 : 10));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = deg % 90 == 0 ? color : Colors.grey
          ..strokeWidth = deg % 90 == 0 ? 3 : 1.5,
      );
    }

    // Jarum: 0 = utara layar. bearing relatif = 0 berarti stadion tepat di depan (utara).
    final angle = (relativeBearing - 90) * math.pi / 180;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * (radius - 26),
      Paint()
        ..color = color
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.relativeBearing != relativeBearing || old.color != color;
}
