import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/database/hive_service.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../../penalty_shootout/data/penalty_rules.dart';
import '../data/blockchain.dart';
import '../data/chain_repository.dart';
import '../data/reflex_rules.dart';
import '../data/wallet_repository.dart';
import '../domain/club_card.dart';

/// Alamat dompet Web3 pengguna (checksum EIP-55).
///
/// Dibuat sekali lalu disimpan permanen di secure storage dengan kunci
/// `wallet_private_key`; private key TIDAK pernah dikirim ke jaringan.
/// Alamat ini dipakai sebagai `owner` setiap blok rantai paspor, dan ikut
/// terhapus saat logout (lihat [AuthRepository.logout]) sehingga akun
/// berikutnya tidak memakai dompet milik akun lama.
final walletAddressProvider = FutureProvider<String>(
    (ref) => ref.watch(walletRepositoryProvider).getOrCreateAddress());

// ---------- Rantai blok Paspor ----------

/// Notifier rantai blok paspor.
///
/// State-nya `List<Block>` urut indeks menaik; daftar selalu diawali blok
/// genesis. Sumber penyimpanan: SQLite `sync_documents` collection
/// `passport_chain` (utama) dengan cermin Hive `app_cache` (kunci
/// `passport_chain`) untuk mode offline, jadi setiap penambahan blok menaikkan
/// revisi koleksi dan ikut terkirim pada sinkronisasi.
///
/// Notifier tidak `autoDispose` (rantai dipakai lintas layar), jadi tidak
/// wajib cek `mounted` setelah `await` (aturan §3.5 hanya berlaku untuk
/// notifier `autoDispose`).
class ChainNotifier extends StateNotifier<List<Block>> {
  ChainNotifier(this._repo) : super(_repo.load());
  final ChainRepository _repo;

  /// Tambahkan satu blok baru ke rantai (mining proof-of-work).
  ///
  /// Blok dibangun lewat [Blockchain.next] (PoW difficulty 3), lalu
  /// ditambahkan di akhir daftar dan seluruh rantai disimpan ke SQLite
  /// collection `passport_chain` + Hive `passport_chain`. Efek samping:
  /// penulisan penyimpanan dan (melalui sinkronisasi) pengiriman ke cloud.
  Future<Block> mint(
      String type, Map<String, dynamic> data, String owner) async {
    final block = Blockchain.next(state, type, data, owner);
    state = [...state, block];
    await _repo.save(state);
    return block;
  }

  /// Ganti seluruh rantai dan simpan ke Hive (dipakai pemulihan sinkronisasi).
  ///
  /// Dipanggil sinkronisasi ketika rantai cloud valid dan rekonsiliasi
  /// memutuskan "cloud wins". Efek samping: menulis ulang SQLite collection
  /// `passport_chain` dan Hive `passport_chain`.
  Future<void> replaceAll(List<Block> chain) async {
    state = chain;
    await _repo.save(chain);
  }
}

/// Rantai blok paspor pengguna.
///
/// StateProvider biasa (bukan `autoDispose`) karena dipakai lintas layar
/// (paspor, prediksi, stamp, kartu klub); sumber penyimpanan ada di
/// [ChainNotifier].
final chainProvider = StateNotifierProvider<ChainNotifier, List<Block>>(
    (ref) => ChainNotifier(ref.watch(chainRepositoryProvider)));

/// Apakah rantai paspor saat ini valid.
///
/// Provider turunan dari [chainProvider]: memanggil [Blockchain.isValid] yang
/// memeriksa hash, proof-of-work, urutan indeks, dan tautan `prevHash`.
/// Tanpa efek samping.
final chainValidProvider =
    Provider<bool>((ref) => Blockchain.isValid(ref.watch(chainProvider)));

/// Blok bertipe `stamp` (cap stamp stadion) dari rantai paspor.
///
/// Provider turunan dari [chainProvider]; urutan mengikuti urutan blok di
/// rantai. Tanpa efek samping.
final stampsProvider = Provider<List<Block>>(
    (ref) => ref.watch(chainProvider).where((b) => b.type == 'stamp').toList());

// ---------- Kartu klub: satu blok 'card' per milestone ----------

/// Kartu terakhir yang berhasil di-mint, untuk dikonsumsi UI (Fase 3).
///
/// State di memori (bukan Hive): nilainya hilang saat aplikasi ditutup, dan
/// sengaja tidak disimpan karena kartu dapat diturunkan ulang dari rantai.
final lastEarnedCardProvider = StateProvider<ClubCard?>((ref) => null);

/// Pencetak kartu klub untuk satu provider.
final cardMinterProvider = Provider<CardMinter>((ref) => CardMinter(ref));

/// Mencetak satu blok `card` per milestone.
///
/// Dedup membaca rantai itu sendiri (blok tipe `card` dengan `data['ref']` yang
/// sama), bukan flag terpisah, sehingga tetap berlaku setelah reinstall atau
/// pemulihan dari cloud. Mint memakai jalur yang sama dengan blok lain
/// (PoW + persist + sinkronisasi) lewat [ChainNotifier.mint]; tidak ada logika
/// mining yang diduplikasi.
class CardMinter {
  CardMinter(this._ref);
  final Ref _ref;

  /// Kembalikan kartu yang baru dicetak, atau null bila [ref] sudah pernah
  /// dicetak / blok gagal dibuat. Kegagalan tidak boleh mengganggu alur game,
  /// prediksi, atau stamp: semua error ditelan, di-log, dan jadi null.
  ///
  /// Efek samping: satu blok `card` ditambahkan ke rantai paspor (SQLite
  /// collection `passport_chain` + Hive `passport_chain`) dan
  /// [lastEarnedCardProvider] diperbarui dengan kartu yang baru dicetak.
  Future<ClubCard?> mintCard({
    required String source,
    required String ref,
  }) async {
    try {
      final already = _ref
          .read(chainProvider)
          .any((b) => b.type == 'card' && b.data['ref']?.toString() == ref);
      if (already) return null;

      final owner = await _ref.read(walletAddressProvider.future);
      final block = await _ref
          .read(chainProvider.notifier)
          .mint('card', {'source': source, 'ref': ref}, owner);

      final clubs = await _ref.read(clubsProvider.future);
      final card = cardFromBlock(block, [for (final c in clubs) c.key]);
      if (card != null) {
        _ref.read(lastEarnedCardProvider.notifier).state = card;
      }
      return card;
    } catch (e) {
      debugPrint('mintCard gagal (source=$source, ref=$ref): $e');
      return null;
    }
  }
}

// ---------- Cap stamp: wajib dekat stadion (atau mode demo) ----------
// Radius ini disepakati di rubrik: 800 m.
const stampRadiusMeters = 800.0;

/// Mode demo: melewati verifikasi GPS (dicatat gps_verified=false di blok).
///
/// State lokal UI (bukan `autoDispose`) yang menentukan apakah cap stamp boleh
/// dilakukan tanpa benar-benar berada dekat stadion. Hanya preferensi tampilan,
/// tanpa efek samping penyimpanan.
final demoModeProvider = StateProvider<bool>((ref) => false);

/// Jarak (meter) dari posisi pengguna ke stadion klub favorit, atau null bila
/// GPS belum aktif / izin lokasi belum diberikan.
///
/// Sengaja TIDAK meminta izin sendiri: pemicunya tetap tombol "Cap stamp"
/// lewat confirmPermission, supaya rationale tampil sebelum permintaan OS.
///
/// Provider `autoDispose`: izin dan posisi diambil setiap kali dibaca, dan
/// stream GPS tidak dipertahankan setelah layar ditutup. Efek samping:
/// membaca sensor GPS (bukan memutarnya terus-menerus).
final stampDistanceProvider = FutureProvider.autoDispose<int?>((ref) async {
  final club = ref.watch(favoriteClubProvider);
  if (club == null) return null;
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  final perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    return null;
  }
  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
    return Geolocator.distanceBetween(
            pos.latitude, pos.longitude, club.lat, club.lng)
        .round();
  } catch (_) {
    return null;
  }
});

/// Notifier cap stamp (mencetak cap stadion ke rantai paspor).
///
/// State-nya `AsyncValue<String?>`: `null` berarti belum ada aksi, `loading`
/// selama proses, dan `data` berisi pesan sukses berisi nomor blok. Galat
/// ditampilkan sebagai [AsyncError] dengan pesan Bahasa Indonesia.
///
/// Aturan §3.5 (penting): notifier ini `autoDispose` DAN melakukan `await`
/// (izin lokasi + GPS + mint blok + kartu), jadi sebelum menyentuh `state`
/// setelah `await` selalu diperiksa `if (!mounted) return;` — tanpa itu,
/// layar yang ditutup di tengah proses akan membuat error saat memperbarui
/// state. Selain itu, seluruh dependensi (ref) dibaca SEBELUM `await`
/// pertama supaya `ref` tidak dipakai setelah provider di-dispose.
class StampNotifier extends StateNotifier<AsyncValue<String?>> {
  StampNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;

  /// Cap klub [club] sebagai blok `stamp` di rantai paspor.
  ///
  /// Alurnya: tolak bila cap untuk stadion itu sudah ada, verifikasi jarak
  /// ke stadion (kecuali [demoModeProvider] menyala — saat itu GPS dilewati
  /// dan `gps_verified` dicatat false), lalu mint blok `stamp` lewat
  /// [ChainNotifier.mint] dan (bukan demo) juga mencetak kartu klub.
  ///
  /// Efek samping: meminta izin lokasi dan membaca GPS, menambah blok ke
  /// rantai paspor (SQLite collection `passport_chain` + Hive
  /// `passport_chain`), memperbarui [lastEarnedCardProvider], dan
  /// meng-invalidate [stampDistanceProvider] setelah sukses.
  Future<void> stamp(PlClub club) async {
    final demo = _ref.read(demoModeProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      // Semua dependensi dibaca SEBELUM await: ref tidak boleh dipakai
      // setelah provider di-dispose.
      final already = _ref.read(stampsProvider).any((b) =>
          b.data['club'] == club.key && b.data['stadium'] == club.stadium);
      if (already) throw Exception('Stamp ${club.stadium} sudah dimiliki');

      var distance = 0;
      if (!demo) {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw Exception(
              'Lokasi GPS belum aktif. Nyalakan lokasi perangkat lalu coba lagi.');
        }
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          throw Exception('Izin lokasi ditolak');
        }
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        distance = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, club.lat, club.lng)
            .round();
        if (distance > stampRadiusMeters) {
          throw Exception(
              'Anda ${distance}m dari ${club.stadium}. Harus dalam ${stampRadiusMeters.round()}m.');
        }
      }
      final owner = await _ref.read(walletAddressProvider.future);
      final block = await _ref.read(chainProvider.notifier).mint(
          'stamp',
          {
            'club': club.key,
            'stadium': club.stadium,
            'gps_verified': !demo,
            'distance_m': distance,
          },
          owner);
      if (!demo) {
        await _ref
            .read(cardMinterProvider)
            .mintCard(source: 'stamp', ref: 'stamp:${club.key}');
      }
      return 'Stamp ${club.stadium} tercetak (catatan #${block.index})';
    });
    if (!mounted) return; // layar sudah ditutup
    state = result;
    if (!demo) _ref.invalidate(stampDistanceProvider);
  }
}

/// State cap stamp (pesan sukses / galat / loading) untuk layar paspor.
///
/// `autoDispose`: notifier dan state-nya dibuang saat layar ditutup sehingga
/// tidak ada aksi stamp yang tertunda tanpa pengawas.
final stampProvider =
    StateNotifierProvider.autoDispose<StampNotifier, AsyncValue<String?>>(
        (ref) => StampNotifier(ref));

// ---------- Refleks Kiper ----------

/// State lengkap mini game Refleks Kiper.
///
/// Membungkus skor, sisa nyawa, combo, level, zona gawang yang dibuka, progres
/// waktu (di-derive dari [ballProgress]), status berjalan/selesai, dan skor
/// tertinggi yang tersimpan. Nilai immutable; perubahan dilakukan lewat
/// [copyWith].
class ReflexState {
  const ReflexState({
    this.score = 0,
    this.lives = reflexLives,
    this.combo = 0,
    this.saves = 0,
    this.level = 1,
    this.zone,
    this.running = false,
    this.gameOver = false,
    this.timeLimitMs = initialReflexTimeLimitMs,
    this.remainingMs = initialReflexTimeLimitMs,
    this.bestScore = 0,
  });

  final int score;
  final int lives;
  final int combo;
  final int saves;
  final int level;
  final KickZone? zone;
  final bool running;
  final bool gameOver;
  final int timeLimitMs;
  final int remainingMs;
  final int bestScore;

  /// Progres gawang yang bergerak maju, 0..1; 1 berarti waktu habis.
  double get ballProgress {
    if (timeLimitMs <= 0) return 1;
    return (1 - remainingMs / timeLimitMs).clamp(0.0, 1.0).toDouble();
  }

  ReflexState copyWith({
    int? score,
    int? lives,
    int? combo,
    int? saves,
    int? level,
    KickZone? zone,
    bool clearZone = false,
    bool? running,
    bool? gameOver,
    int? timeLimitMs,
    int? remainingMs,
    int? bestScore,
  }) =>
      ReflexState(
        score: score ?? this.score,
        lives: lives ?? this.lives,
        combo: combo ?? this.combo,
        saves: saves ?? this.saves,
        level: level ?? this.level,
        zone: clearZone ? null : (zone ?? this.zone),
        running: running ?? this.running,
        gameOver: gameOver ?? this.gameOver,
        timeLimitMs: timeLimitMs ?? this.timeLimitMs,
        remainingMs: remainingMs ?? this.remainingMs,
        bestScore: bestScore ?? this.bestScore,
      );
}

/// Notifier mini game Refleks Kiper.
///
/// State-nya [ReflexState]. Game dimulai dengan [start], bola digulir
/// menuju satu zona gawang, dan pemain harus menepis sebelum [ballProgress]
/// mencapai 1. Berhasil menepis menaikkan combo/level/skor; meleset
/// mengurangi nyawa, dan nyawa 0 mengakhiri permainan.
///
/// Aturan §3.5: notifier ini `autoDispose` dan memakai `Timer` yang memicu
/// `await` di [_finishGame], jadi SEBELUM menyentuh `state` setelah `await`
/// selalu diperiksa `if (!mounted) return;` (baik di timer maupun di
/// [_finishGame] setelah Hive ditulis). Tanpa itu, layar yang ditutup
/// di tengah permainan akan membuat error saat memperbarui state.
///
/// Skor tertinggi dan blok harian disimpan di Hive `app_cache` (kunci
/// `reflex_best` dan `reflex_block_day`).
class ReflexNotifier extends StateNotifier<ReflexState> {
  ReflexNotifier(this._ref) : super(ReflexState(bestScore: _readBestScore()));

  final Ref _ref;
  final Random _rnd = Random();
  Timer? _ballTimer;
  DateTime? _ballStartedAt;

  static int _readBestScore() {
    try {
      return int.tryParse(HiveService.cache.get('reflex_best') ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Mulai sesi permainan baru di level 1.
  ///
  /// Menghitung ulang batas waktu level 1, memilih zona gawang pertama, lalu
  /// menjalankan timer bola 40 ms. Skor tertinggi lama dipertahankan.
  /// Tidak ada efek samping penyimpanan.
  void start() {
    _cancelTimer();
    final limit = timeLimitForLevel(1);
    state = ReflexState(
      running: true,
      zone: pickZone(_rnd, null),
      timeLimitMs: limit,
      remainingMs: limit,
      bestScore: state.bestScore,
    );
    _startBallTimer();
  }

  /// Pemain menepis pada [tappedZone]; menentukan berhasil atau meleset.
  ///
  /// Tidak berpengaruh bila permainan tidak sedang berjalan atau zona belum
  /// ditentukan. Tanpa efek samping penyimpanan.
  void tapZone(KickZone tappedZone) {
    if (!state.running || state.zone == null) return;
    if (tappedZone != state.zone) {
      _miss();
      return;
    }
    _save();
  }

  void _save() {
    _cancelTimer();
    final combo = comboAfterSave(state.combo);
    final saves = state.saves + 1;
    final level = levelForSaves(saves);
    final limit = timeLimitForLevel(level);
    final score = state.score + scoreForSave(combo);
    state = state.copyWith(
      score: score,
      lives: state.lives,
      combo: combo,
      saves: saves,
      level: level,
      zone: pickZone(_rnd, state.zone),
      running: true,
      gameOver: false,
      timeLimitMs: limit,
      remainingMs: limit,
      bestScore: score > state.bestScore ? score : state.bestScore,
    );
    _startBallTimer();
  }

  void _miss() {
    if (!state.running) return;
    _cancelTimer();
    final lives = livesAfterMiss(state.lives);
    if (lives == 0) {
      final bestScore =
          state.score > state.bestScore ? state.score : state.bestScore;
      state = state.copyWith(
        lives: 0,
        combo: comboAfterMiss(state.combo),
        running: false,
        gameOver: true,
        clearZone: true,
        remainingMs: 0,
        bestScore: bestScore,
      );
      _finishGame();
      return;
    }

    state = state.copyWith(
      lives: lives,
      combo: comboAfterMiss(state.combo),
      zone: pickZone(_rnd, state.zone),
      running: true,
      remainingMs: state.timeLimitMs,
    );
    _startBallTimer();
  }

  void _startBallTimer() {
    _ballStartedAt = DateTime.now();
    _ballTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted || !state.running) {
        _cancelTimer();
        return;
      }
      final elapsed = DateTime.now()
          .difference(_ballStartedAt ?? DateTime.now())
          .inMilliseconds;
      final remaining = state.timeLimitMs - elapsed;
      if (remaining <= 0) {
        _miss();
      } else {
        state = state.copyWith(remainingMs: remaining);
      }
    });
  }

  /// Tangani akhir permainan: simpan skor tertinggi dan (sekali sehari, bila
  /// skor >= 100) mint blok `achievement` + kartu klub.
  ///
  /// Aturan §3.5: metode ini `await` Hive, wallet, dan mint; setiap `await`
  /// dibuntuti pemeriksaan `if (!mounted) return;` sehingga layar yang sudah
  /// ditutup tidak lagi menyentuh `state`. Efek samping: menulis Hive
  /// `app_cache` (kunci `reflex_best` dan `reflex_block_day`), menambah blok
  /// `achievement` ke rantai paspor, dan memperbarui
  /// [lastEarnedCardProvider].
  Future<void> _finishGame() async {
    final score = state.score;
    final saves = state.saves;
    final level = state.level;
    final bestScore = state.bestScore;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final shouldMint =
        score >= 100 && HiveService.cache.get('reflex_block_day') != today;

    final Future<String>? walletFuture =
        shouldMint ? _ref.read(walletAddressProvider.future) : null;
    final chain = shouldMint ? _ref.read(chainProvider.notifier) : null;

    await HiveService.cache.put('reflex_best', '$bestScore');
    if (!mounted || !shouldMint) return;

    final owner = await walletFuture!;
    if (!mounted) return;
    await chain!.mint(
      'achievement',
      {
        'game': 'Refleks Kiper',
        'score': score,
        'saves': saves,
        'level': level,
      },
      owner,
    );
    if (!mounted) return;
    await _ref
        .read(cardMinterProvider)
        .mintCard(source: 'reflex', ref: 'reflex:$today');
    if (!mounted) return;
    await HiveService.cache.put('reflex_block_day', today);
  }

  void _cancelTimer() {
    _ballTimer?.cancel();
    _ballTimer = null;
    _ballStartedAt = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}

/// State mini game Refleks Kiper untuk layar game.
///
/// `autoDispose`: notifier dibuang saat layar ditutup, sehingga timer bola
/// 40 ms ikut berhenti otomatis (lihat [ReflexNotifier.dispose]) dan tidak
/// membebani baterai. Skor tertinggi tetap bertahan di Hive `app_cache`
/// (kunci `reflex_best`).
final reflexProvider =
    StateNotifierProvider.autoDispose<ReflexNotifier, ReflexState>(
  (ref) => ReflexNotifier(ref),
);
