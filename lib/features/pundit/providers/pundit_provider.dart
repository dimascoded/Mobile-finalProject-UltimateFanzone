import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_config.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/pundit_chat.dart';
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

/// Status tab "Tanya Pundit".
class PunditChatState {
  const PunditChatState({
    this.messages = const [],
    this.sending = false,
    this.error,
    this.failedText,
  });

  final List<ChatMessage> messages;
  final bool sending;
  final String? error;

  /// Teks pertanyaan terakhir yang gagal dikirim; bila terisi, layar menampilkan
  /// tombol "Kirim ulang".
  final String? failedText;
}

/// Notifier percakapan "Tanya Pundit" untuk tim favorit saat ini.
class PunditChatNotifier extends StateNotifier<PunditChatState> {
  PunditChatNotifier(this._ref) : super(const PunditChatState()) {
    _load();
  }

  final Ref _ref;

  static const _maxInputChars = 500;

  /// Muat riwayat klub yang sedang difavoritkan.
  void _load() {
    final club = _ref.read(favoriteClubProvider);
    if (club == null) return;
    state = PunditChatState(
      messages: _ref.read(punditRepositoryProvider).loadChat(club.key),
    );
  }

  /// Tiga laga berikutnya milik [club] dari data pertandingan.
  List<FootballMatch> _upcoming(PlClub club) {
    final data =
        _ref.read(matchesProvider).valueOrNull?.data ?? const <FootballMatch>[];
    final now = DateTime.now().toUtc();
    final list = data
        .where((m) {
          final phase = m.phaseAt(now);
          final soon = phase == MatchPhase.upcoming || phase == MatchPhase.live;
          return soon && m.involves(club);
        })
        .toList()
      ..sort((a, b) => a.kickoffUtc.compareTo(b.kickoffUtc));
    return list.take(3).toList();
  }

  PunditChatState _withError(String message) => PunditChatState(
        messages: state.messages,
        sending: false,
        error: message,
        failedText: state.failedText,
      );

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;
    final capped = trimmed.length > _maxInputChars
        ? trimmed.substring(0, _maxInputChars)
        : trimmed;

    final club = _ref.read(favoriteClubProvider);
    if (club == null) {
      state =
          _withError('Pilih tim favorit dulu untuk mengobrol dengan pundit.');
      return;
    }
    if (AppConfig.geminiApiKey.isEmpty) {
      state = _withError('GEMINI_API_KEY belum diset (gunakan --dart-define).');
      return;
    }

    final messages = [
      ...state.messages,
      ChatMessage(role: 'user', text: capped, at: DateTime.now().toUtc()),
    ];
    state = PunditChatState(messages: messages, sending: true);
    await _reply(messages, capped);
  }

  /// Kirim ulang pertanyaan yang gagal tanpa menggandakan pesan pengguna.
  Future<void> retry() async {
    final failed = state.failedText;
    if (failed == null || state.sending) return;
    final messages = state.messages;
    if (messages.isEmpty || messages.last.role != 'user') return;
    state = PunditChatState(messages: messages, sending: true);
    await _reply(messages, failed);
  }

  Future<void> _reply(List<ChatMessage> messages, String failedText) async {
    final club = _ref.read(favoriteClubProvider);
    if (club == null) {
      state =
          _withError('Pilih tim favorit dulu untuk mengobrol dengan pundit.');
      return;
    }
    final standings =
        _ref.read(standingsProvider).valueOrNull?.data ?? const [];
    final last5 = _ref.read(lastResultsProvider).take(5).toList();
    final instruction = buildSystemInstruction(
      club: club,
      standings: standings,
      last5: last5,
      upcoming: _upcoming(club),
    );
    final repo = _ref.read(punditRepositoryProvider);
    try {
      final reply = await repo.chatReply(
        systemInstruction: instruction,
        turns: trimTurns(messages),
      );
      final next = [
        ...messages,
        ChatMessage(role: 'model', text: reply, at: DateTime.now().toUtc()),
      ];
      await repo.saveChat(club.key, next);
      if (!mounted) return;
      state = PunditChatState(messages: next);
    } catch (e) {
      if (!mounted) return;
      state = PunditChatState(
        messages: messages,
        error: e.toString().replaceFirst('Exception: ', ''),
        failedText: failedText,
      );
    }
  }

  /// Kosongkan percakapan di memori dan di penyimpanan.
  Future<void> clear() async {
    final club = _ref.read(favoriteClubProvider);
    state = const PunditChatState();
    if (club != null) {
      await _ref.read(punditRepositoryProvider).saveChat(club.key, const []);
    }
  }
}

/// Dibangun ulang setiap kali tim favorit berganti supaya riwayat yang
/// ditampilkan selalu milik klub yang sedang aktif.
final punditChatProvider =
    StateNotifierProvider<PunditChatNotifier, PunditChatState>((ref) {
  ref.watch(favoriteClubProvider);
  return PunditChatNotifier(ref);
});
