import 'package:flutter/material.dart';

class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kesan & Pesan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Mata Kuliah Pemrograman Aplikasi Mobile',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kesan', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Mata kuliah Pemrograman Aplikasi Mobile memberikan '
                    'pengalaman belajar yang menarik dalam merancang dan '
                    'membangun aplikasi. Saya mendapat pemahaman baru tentang '
                    'Flutter, pengelolaan state, penyimpanan data, integrasi '
                    'layanan, dan proses menguji aplikasi pada perangkat.',
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pesan', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Semoga pembelajaran dan praktikum terus memberi ruang '
                    'untuk mencoba ide sendiri, membahas proses debugging, '
                    'serta mengembangkan aplikasi yang bermanfaat. Terima '
                    'kasih atas materi dan bimbingan selama perkuliahan.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
