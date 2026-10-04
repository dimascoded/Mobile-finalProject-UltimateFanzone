import 'package:flutter/material.dart';
import '../../../core/utils/time_utils.dart';

/// Jam kickoff dalam WIB, WITA, WIT, dan London dari waktu UTC.
class KickoffTimes extends StatelessWidget {
  const KickoffTimes({super.key, required this.utc, this.light = false});
  final DateTime utc;
  final bool light; // true = teks terang (di atas latar gelap)

  @override
  Widget build(BuildContext context) {
    final wib = TimeUtils.wib(utc);
    final color = light ? Colors.white : null;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        '${TimeUtils.formatDate(wib)} • ${TimeUtils.formatHm(wib)} WIB',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(
        'WITA ${TimeUtils.formatHm(TimeUtils.wita(utc))}  •  '
        'WIT ${TimeUtils.formatHm(TimeUtils.wit(utc))}  •  '
        'London ${TimeUtils.formatHm(TimeUtils.london(utc))}',
        style: small,
      ),
    ]);
  }
}

/// Laga yang kickoff antara 00.00 dan 04.59 WIB (penonton harus begadang).
bool isDiniHari(DateTime utc) => TimeUtils.wib(utc).hour < 5;
