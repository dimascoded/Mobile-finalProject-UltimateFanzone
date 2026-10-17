import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/time_utils.dart';
import '../../football/presentation/club_crest.dart';
import '../../football/providers/football_providers.dart';
import '../data/pundit_chat.dart';
import '../providers/pundit_provider.dart';

class PunditScreen extends ConsumerWidget {
  const PunditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pundit AI'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Analisis'),
              Tab(text: 'Tanya Pundit'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AnalysisTab(),
            PunditChatTab(),
          ],
        ),
      ),
    );
  }
}

class _AnalysisTab extends ConsumerWidget {
  const _AnalysisTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(punditProvider);
    final club = ref.watch(favoriteClubProvider);
    final crests = ref.watch(clubCrestProvider);
    final loading = state.isLoading;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (club != null)
              Row(children: [
                ClubCrest(
                  crestUrl: crests[club.tla.toUpperCase()],
                  tla: club.tla,
                  color: club.colorValue,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Tim favorit: ${club.name}')),
              ]),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: loading
                  ? null
                  : () => ref.read(punditProvider.notifier).generate(),
              icon: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label:
                  Text(loading ? 'Menulis analisis…' : 'Buat Analisis Pundit'),
            ),
            const SizedBox(height: AppSpacing.md),
            state.when(
              data: (r) {
                if (r == null) {
                  return const Text(
                      'Belum ada analisis. Tekan tombol di atas.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.warning != null)
                      Card(
                        color: scheme.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 20, color: scheme.onTertiaryContainer),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Analisis terbaru gagal dimuat, jadi yang tampil '
                                  'adalah hasil tersimpan. ${r.warning}',
                                  style: TextStyle(
                                      color: scheme.onTertiaryContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (r.fromCache)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Chip(
                          avatar: const Icon(Icons.history, size: 18),
                          label: Text(r.cachedAt == null
                              ? 'Data tersimpan (tanpa waktu)'
                              : 'Data tersimpan • ${TimeUtils.formatHm(TimeUtils.wib(r.cachedAt!))} WIB'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    Text(r.text,
                        style:
                            theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Analisis gagal', style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(e.toString().replaceFirst('Exception: ', '')),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(punditProvider.notifier).generate(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba lagi'),
                      ),
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

class PunditChatTab extends ConsumerStatefulWidget {
  const PunditChatTab({super.key});

  @override
  ConsumerState<PunditChatTab> createState() => _PunditChatTabState();
}

class _PunditChatTabState extends ConsumerState<PunditChatTab> {
  static const _suggestions = [
    'Prediksi laga berikutnya?',
    'Bagaimana performa 5 laga terakhir?',
    'Siapa lawan terberat musim ini?',
  ];

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _controller.clear();
    await ref.read(punditChatProvider.notifier).send(trimmed);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus percakapan?'),
        content: const Text(
            'Seluruh riwayat tanya jawab dengan pundit akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(punditChatProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(punditChatProvider);
    ref.listen(punditChatProvider, (_, __) => _scrollToBottom());
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tanya Pundit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Hapus percakapan',
                onPressed: (state.messages.isEmpty && !state.sending)
                    ? null
                    : _confirmClear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: (state.messages.isEmpty && !state.sending)
              ? _EmptyChat(suggestions: _suggestions, onTap: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: state.messages.length,
                  itemBuilder: (context, i) =>
                      _Bubble(message: state.messages[i]),
                ),
        ),
        if (state.sending)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Pundit sedang menulis…'),
              ],
            ),
          ),
        if (state.error != null)
          _ErrorBanner(
            error: state.error!,
            canRetry: state.failedText != null,
            onRetry: () => ref.read(punditChatProvider.notifier).retry(),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !state.sending,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: state.sending ? null : _send,
                      decoration: const InputDecoration(
                        hintText: 'Tulis pertanyaan tentang tim favoritmu…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: 'Kirim',
                    onPressed:
                        state.sending ? null : () => _send(_controller.text),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
              Text(
                'Jawaban AI bisa keliru, bukan saran taruhan.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.suggestions, required this.onTap});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.forum_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Belum ada percakapan. Coba tanya salah satu ini:',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => onTap(suggestion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: SelectableText(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isUser ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.error,
    required this.canRetry,
    required this.onRetry,
  });

  final String error;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (canRetry)
            TextButton(
              onPressed: onRetry,
              child: const Text('Kirim ulang'),
            ),
        ],
      ),
    );
  }
}
