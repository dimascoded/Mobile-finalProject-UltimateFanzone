import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../football/providers/football_providers.dart';
import '../../football/data/models.dart';
import '../data/pundit_repository.dart';

final lastResultsProvider = Provider<List<FootballMatch>>((ref) {
  final fav = ref.watch(favoriteClubProvider);
  return ref.watch(matchesProvider).maybeWhen(
        data: (r) => r.data
            .where((m) => fav != null && m.involves(fav) && m.isFinished)
            .toList()
          ..sort((a, b) => b.kickoffUtc.compareTo(a.kickoffUtc)),
        orElse: () => const [],
      );
});

class PunditNotifier extends StateNotifier<AsyncValue<PunditResult?>> {
  PunditNotifier(this.ref) : super(const AsyncData(null));
  final Ref ref;

  Future<void> generate() async {
    final club = ref.read(favoriteClubProvider);
    final standings = ref.read(standingsProvider).valueOrNull?.data ?? [];
    final last5 = ref.read(lastResultsProvider).take(5).toList();
    if (club == null) {
      state = AsyncError(Exception('Pilih tim favorit dulu'), StackTrace.current);
      return;
    }
    state = const AsyncLoading();
    final repo = ref.read(punditRepositoryProvider);
    try {
      final r = await repo.generate(club, standings, last5);
      if (mounted) state = AsyncData(r);
    } catch (e, st) {
      final cache = repo.cached(club.key);
      if (mounted) state = cache != null ? AsyncData(cache) : AsyncError(e, st);
    }
  }
}

final punditProvider = StateNotifierProvider<PunditNotifier, AsyncValue<PunditResult?>>((ref) {
  final club = ref.watch(favoriteClubProvider);
  final repo = ref.watch(punditRepositoryProvider);
  final notifier = PunditNotifier(ref);
  notifier.state = AsyncData(repo.cached(club?.key));
  return notifier;
});