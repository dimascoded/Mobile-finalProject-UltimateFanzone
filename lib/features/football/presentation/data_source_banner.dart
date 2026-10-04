import 'package:flutter/material.dart';
import '../../../core/utils/time_utils.dart';
import '../data/football_repository.dart';

class DataSourceBanner extends StatelessWidget {
  const DataSourceBanner({super.key, required this.source, this.fetchedAt});
  final DataSource source;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final String text;
    late final IconData icon;
    late final Color bg, fg;
    switch (source) {
      case DataSource.sample:
        text = 'DATA CONTOH - bukan jadwal resmi. Isi FOOTBALL_API_KEY untuk data asli.';
        icon = Icons.science;
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
      case DataSource.cache:
        text = 'Data tersimpan'
            '${fetchedAt == null ? '' : ' • ${TimeUtils.formatHm(fetchedAt!)}'}'
            ' (skor gratis tertunda)';
        icon = Icons.history;
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
      case DataSource.live:
        text = 'Diperbarui'
            '${fetchedAt == null ? '' : ' ${TimeUtils.formatHm(fetchedAt!)}'}'
            ' • skor pada tier gratis bisa tertunda';
        icon = Icons.cloud_done;
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: fg))),
      ]),
    );
  }
}
