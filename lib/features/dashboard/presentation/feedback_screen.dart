import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/ui/app_card.dart';

// STRUKTUR UI — FeedbackScreen
// Ukuran: Scaffold > Center > ConstrainedBox(maxWidth 720) > ListView.
// [1] Judul           — "Mata Kuliah Pemrograman Aplikasi Mobile"
// [2] AppCard Kesan   — paragraf kesan tentang pembelajaran Flutter
// [3] AppCard Pesan   — paragraf pesan untuk Perkuliahan
// Tabel/kolom: tanpa tabel; dua kartu teks satu kolom.
// Sumber data: tanpa provider; isi teks statis di dalam file.
class FeedbackScreen extends StatelessWidget {
  const FeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kesan & Pesan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                'Mata Kuliah Pemrograman Aplikasi Mobile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kesan', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
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
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pesan', style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Semoga pembelajaran dan praktikum terus memberi ruang '
                      'untuk mencoba ide sendiri, membahas proses debugging, '
                      'serta mengembangkan aplikasi yang bermanfaat. Terima '
                      'kasih atas materi dan bimbingan selama perkuliahan.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
