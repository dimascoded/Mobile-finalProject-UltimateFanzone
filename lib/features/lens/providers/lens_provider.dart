import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/rates_provider.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/lens_repository.dart';
import '../data/price_parser.dart';

class LensPrice {
  const LensPrice(this.line, this.amount, this.idr);
  final String line;
  final double amount;
  final double? idr; // null jika kurs gagal dimuat (offline)
}

class LensResult {
  const LensResult({
    required this.imagePath,
    required this.text,
    required this.currency,
    required this.prices,
    this.mentionedClubs = const [],
    this.ratesFromCache = false,
  });
  final String imagePath, text, currency;
  final List<LensPrice> prices;

  /// Klub Premier League yang namanya terbaca di teks OCR. UI7: sebelumnya
  /// hasil scan tidak pernah dicocokkan ke klub mana pun, jadi pengguna
  /// tidak tahu foto struk/karcis itu milik tim yang mana.
  final List<PlClub> mentionedClubs;

  /// true bila konversi Rupiah memakai kurs dari cache Hive, bukan request baru.
  final bool ratesFromCache;
}

/// Cocokkan teks OCR dengan daftar klub lewat [PlClub.isTeam].
///
/// Kode tim ("ARS", "MCI") sering berdiri sendiri di struk, jadi TLA dicocokkan
/// per token. Pencocokan token memakai batas kata supaya "ARS" tidak ikut
/// cocok di dalam kata lain; alias nama tetap pakai [PlClub.isTeam] yang sudah
/// menoleransi akhiran "FC"/"AFC".
List<PlClub> detectClubs(String text, List<PlClub> clubs) {
  final found = <PlClub>[];
  for (final line in text.split('\n')) {
    final clean = line.trim();
    if (clean.isEmpty) continue;
    final tokens = clean
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .map((t) => t.toUpperCase())
        .toSet();
    for (final c in clubs) {
      if (found.contains(c)) continue;
      final byTla = tokens.contains(c.tla.toUpperCase());
      if (byTla || c.isTeam(clean, null)) found.add(c);
    }
  }
  return found;
}

class LensNotifier extends StateNotifier<AsyncValue<LensResult?>> {
  LensNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;
  final _picker = ImagePicker();

  Future<void> scan(ImageSource source) async {
    final club = _ref.read(favoriteClubProvider);
    const currency = 'GBP';
    if (club == null) {
      state =
          AsyncError(Exception('Pilih tim favorit dulu'), StackTrace.current);
      return;
    }
    final x = await _picker.pickImage(
        source: source, maxWidth: 1600, imageQuality: 90);
    if (x == null) return;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final text = await _ref.read(lensRepositoryProvider).recognize(x.path);
      final found = PriceParser.extract(text, currency);

      // C2: `ratesProvider` sudah mengembalikan cache Hive saat offline,
      // jadi `null` di sini berarti benar-benar tidak ada kurs sama sekali.
      RatesSnapshot? snap;
      try {
        snap = await _ref.read(ratesProvider.future);
      } catch (_) {
        snap = null; // tetap tampilkan harga mentah
      }
      final rate = snap?.gbpPerIdr;
      final clubs = _ref.read(clubsProvider).valueOrNull ?? const <PlClub>[];
      return LensResult(
        imagePath: x.path,
        text: text,
        currency: currency,
        mentionedClubs: detectClubs(text, clubs),
        ratesFromCache: snap?.fromCache ?? false,
        prices: [
          for (final p in found)
            LensPrice(p.line, p.amount,
                rate == null || rate == 0 ? null : p.amount / rate),
        ],
      );
    });
    if (!mounted) return;
    state = result;
  }

  void clear() => state = const AsyncData(null);
}

final lensProvider =
    StateNotifierProvider.autoDispose<LensNotifier, AsyncValue<LensResult?>>(
        (ref) => LensNotifier(ref));
