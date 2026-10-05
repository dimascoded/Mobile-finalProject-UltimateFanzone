import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/permission_gate.dart';
import '../../football/data/models.dart';
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
                  child: Text('${c.name} - ${c.stadium}',
                      overflow: TextOverflow.ellipsis),
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
    required this.position,
    required this.heading,
    required this.onRefresh,
  });

  final PlClub? target;
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
          _CompassDial(relativeBearing: relative, color: club.colorValue),
          const SizedBox(height: 20),
          Text(club.name, style: Theme.of(context).textTheme.titleLarge),
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
