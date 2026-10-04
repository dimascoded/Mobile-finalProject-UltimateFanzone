import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../football/providers/football_providers.dart';
import '../providers/ar_providers.dart';

class StadiumPointerScreen extends ConsumerWidget {
  const StadiumPointerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubs = ref.watch(clubsProvider).valueOrNull ?? [];
    final target = ref.watch(selectedStadiumProvider);
    final pos = ref.watch(positionProvider);
    final compass = ref.watch(compassProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kompas Stadion')),
      body: Column(children: [
        DropdownButton<PlClub>(
          value: target ?? (clubs.isNotEmpty ? clubs.first : null),
          items: clubs.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
          onChanged: (v) {
            final i = clubs.indexOf(v!);
            ref.read(selectedStadiumIndexProvider.notifier).state = i;
          },
        ),
        if (target != null && pos.hasValue && compass.hasValue)
          _buildInfo(context, target, pos.value!, compass.value),
      ]),
    );
  }

  Widget _buildInfo(BuildContext context, club, Position p, double heading) {
    final info = computePointer(p, club);
    final diff = (info.bearing - heading + 360) % 360;
    return Column(children: [
      Text(club.stadium),
      Text('${info.distanceKm.toStringAsFixed(2)} km'),
      Text('Bearing ${info.bearing.toStringAsFixed(1)}°'),
    ]);
  }
}