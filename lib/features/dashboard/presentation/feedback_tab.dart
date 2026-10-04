import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/dashboard_provider.dart';

class FeedbackTab extends ConsumerStatefulWidget {
  const FeedbackTab({super.key});
  @override
  ConsumerState<FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends ConsumerState<FeedbackTab> {
  late final TextEditingController _kesan;
  late final TextEditingController _saran;

  @override
  void initState() {
    super.initState();
    final f = ref.read(feedbackProvider);
    _kesan = TextEditingController(text: f.kesan);
    _saran = TextEditingController(text: f.saran);
  }

  @override
  void dispose() {
    _kesan.dispose();
    _saran.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Saran dan Kesan', style: Theme.of(context).textTheme.titleLarge),
      const Text('Mata Kuliah Pemrograman Aplikasi Mobile'),
      const SizedBox(height: 16),
      TextField(
        controller: _kesan,
        maxLines: 5,
        decoration: const InputDecoration(
            labelText: 'Kesan', alignLabelWithHint: true),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _saran,
        maxLines: 5,
        decoration: const InputDecoration(
            labelText: 'Saran', alignLabelWithHint: true),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () async {
          await ref.read(feedbackProvider.notifier).save(_kesan.text, _saran.text);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Tersimpan')));
        },
        icon: const Icon(Icons.save),
        label: const Text('Simpan'),
      ),
    ]);
  }
}
