import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/pundit_repository.dart';

/// 5 hasil terakhir. Kalau belum ada tim favorit, pakai semua laga selesai.
final lastResultsProvider = Provider<List<FootballMatch>>((ref) {
  final fav = ref.watch(favoriteClubProvider);
  return ref.watch(matchesProvider).maybeWhen(
        data: (r) {
          final done = r.data.where((m) => m.isFinished).toList();
          final scoped =
              fav == null ? done : done.where((m) => m.involves(fav)).toList();
          return (scoped..sort((a, b) => b.kickoffUtc.compareTo(a.kickoffUtc)));
        },
        orElse: () => const <FootballMatch>[],
      );
});

// State awal diisi lewat super.initialState, bukan lewat `state =` dari luar.
class PunditNotifier extends StateNotifier<AsyncValue<PunditResult?>> {
  PunditNotifier(this._ref, super.initialState);

  final Ref _ref;

  Future<void> generate() async {
    final club = _ref.read(favoriteClubProvider);
    if (club == null) {
      state =
          AsyncError(Exception('Pilih tim favorit dulu'), StackTrace.current);
      return;
    }
    final standings =
        _ref.read(standingsProvider).valueOrNull?.data ?? const [];
    final last5 = _ref.read(lastResultsProvider).take(5).toList();
    final repo = _ref.read(punditRepositoryProvider);

    state = const AsyncLoading();
    try {
      final r = await repo.generate(club, standings, last5);
      if (mounted) state = AsyncData(r);
    } catch (e, st) {
      // Model salah / API key kosong / offline -> pakai hasil cache terakhir,
      // tapi tetap beri tahu lewat [PunditResult.warning] bahwa teksnya bukan
      // hasil request baru. UI6: sebelumnya fallback ini senyap, pengguna
      // mengira analisis barusan dibuat.
      final cache = repo.cached(club.key);
      if (!mounted) return;
      if (cache != null) {
        state = AsyncData(cache.copyWith(
            warning: e.toString().replaceFirst('Exception: ', '')));
      } else {
        state = AsyncError(
            Exception(e.toString().replaceFirst('Exception: ', '')), st);
      }
    }
  }

  void clear() => state = const AsyncData(null);
}

final punditProvider =
    StateNotifierProvider<PunditNotifier, AsyncValue<PunditResult?>>((ref) {
  final club = ref.watch(favoriteClubProvider);
  final repo = ref.watch(punditRepositoryProvider);
  return PunditNotifier(ref, AsyncData(repo.cached(club?.key)));
});
