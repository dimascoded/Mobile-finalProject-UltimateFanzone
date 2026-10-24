import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/ui/app_card.dart';
import '../../../../core/utils/time_utils.dart';
import '../../../football/providers/football_providers.dart';
import '../../providers/world_clock_providers.dart';

/// Widget jam dunia dengan tiga kartu: zona Indonesia, kota Indonesia, dan London.
///
/// Hanya widget ini yang menonton [worldClockProvider]; parent tidak perlu watch.
class WorldClockSection extends ConsumerWidget {
  const WorldClockSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(worldClockProvider);
    final selectedZone = ref.watch(awayDayClockZoneProvider);
    final selectedIndoCity = ref.watch(awayDayClockIndoCityProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Jam dunia',
                    style: Theme.of(context).textTheme.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          clock.when(
            loading: () =>
                const SizedBox(height: 40, child: LinearProgressIndicator()),
            error: (e, _) => Text('Gagal: $e'),
            data: (times) {
              final favorite = ref.watch(favoriteClubProvider);
              final indonesiaTime = times[selectedZone] ?? times['WIB']!;
              final londonTime = times['London']!;
              final indoCity = indonesianCities.firstWhere(
                (c) => c.name == selectedIndoCity,
                orElse: () => indonesianCities.first,
              );
              final cityTime = times[indoCity.zone] ?? times['WIB']!;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 600;

                  if (isWide) {
                    // Three tiles in one row
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ClockTileWithZoneDropdown(
                        key: const ValueKey('clock-readout-zone'),
                        selectedZone: selectedZone,
                        time: indonesiaTime,
                        onZoneChanged: (value) {
                          if (value != null) {
                            ref.read(awayDayClockZoneProvider.notifier).state =
                                value;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ClockTileWithCityDropdown(
                        key: const ValueKey('clock-readout-indo-city'),
                        selectedCity: selectedIndoCity ?? indonesianCities.first.name,
                        time: cityTime,
                        zoneCode: indoCity.zone,
                        onCityChanged: (value) {
                          if (value == null) return;
                          final picked = indonesianCities
                              .firstWhere((c) => c.name == value);
                          ref.read(awayDayClockIndoCityProvider.notifier).state =
                              value;
                          ref.read(awayDayClockZoneProvider.notifier).state =
                              picked.zone;
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ClockTileStatic(
                        key: const ValueKey('clock-readout-london'),
                        label: favorite?.city ?? 'London',
                        time: londonTime,
                        detail: favorite == null
                            ? 'Pilih klub favorit untuk memakai nama kotanya'
                            : 'Jam resmi Inggris (London)',
                      ),
                    ),
                  ],
                );
                  } else {
                    // Tiles 1 and 2 side by side, tile 3 full width below
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _ClockTileWithZoneDropdown(
                                key: const ValueKey('clock-readout-zone'),
                                selectedZone: selectedZone,
                                time: indonesiaTime,
                                onZoneChanged: (value) {
                                  if (value != null) {
                                    ref
                                        .read(awayDayClockZoneProvider.notifier)
                                        .state = value;
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _ClockTileWithCityDropdown(
                                key: const ValueKey('clock-readout-indo-city'),
                                selectedCity:
                                    selectedIndoCity ?? indonesianCities.first.name,
                                time: cityTime,
                                zoneCode: indoCity.zone,
                                onCityChanged: (value) {
                                  if (value == null) return;
                                  final picked = indonesianCities
                                      .firstWhere((c) => c.name == value);
                                  ref
                                      .read(awayDayClockIndoCityProvider.notifier)
                                      .state = value;
                                  ref.read(awayDayClockZoneProvider.notifier).state =
                                      picked.zone;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _ClockTileStatic(
                          key: const ValueKey('clock-readout-london'),
                          label: favorite?.city ?? 'London',
                          time: londonTime,
                          detail: favorite == null
                              ? 'Pilih klub favorit untuk memakai nama kotanya'
                              : 'Jam resmi Inggris (London)',
                        ),
                      ],
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Kartu jam dengan dropdown zona WIB/WITA/WIT sebagai label.
class _ClockTileWithZoneDropdown extends StatelessWidget {
  const _ClockTileWithZoneDropdown({
    super.key,
    required this.selectedZone,
    required this.time,
    required this.onZoneChanged,
  });

  final String selectedZone;
  final DateTime time;
  final ValueChanged<String?> onZoneChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 20,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('clock-zone-$selectedZone'),
                  value: selectedZone,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 12,
                  style: Theme.of(context).textTheme.labelSmall,
                  items: const [
                    DropdownMenuItem(value: 'WIB', child: Text('WIB', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    DropdownMenuItem(value: 'WITA', child: Text('WITA', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    DropdownMenuItem(value: 'WIT', child: Text('WIT', overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ],
                  onChanged: onZoneChanged,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                TimeUtils.format(time),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(TimeUtils.formatDate(time),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
              'Waktu sipil Indonesia',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu jam dengan dropdown kota Indonesia sebagai label.
class _ClockTileWithCityDropdown extends StatelessWidget {
  const _ClockTileWithCityDropdown({
    super.key,
    required this.selectedCity,
    required this.time,
    required this.zoneCode,
    required this.onCityChanged,
  });

  final String selectedCity;
  final DateTime time;
  final String zoneCode;
  final ValueChanged<String?> onCityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: ValueKey('clock-indo-$selectedCity'),
                  value: selectedCity,
                  isExpanded: true,
                  isDense: true,
                  iconSize: 12,
                  style: Theme.of(context).textTheme.labelSmall,
                  items: [
                    for (final c in indonesianCities)
                      DropdownMenuItem(value: c.name, child: Text(c.name, overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ],
                  onChanged: onCityChanged,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                TimeUtils.format(time),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(TimeUtils.formatDate(time),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
              zoneCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu jam statis (tanpa dropdown) untuk London.
class _ClockTileStatic extends StatelessWidget {
  const _ClockTileStatic({
    super.key,
    required this.label,
    required this.time,
    required this.detail,
  });

  final String label;
  final DateTime time;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                TimeUtils.format(time),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(TimeUtils.formatDate(time),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
