import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/rates_provider.dart';
import '../../football/data/models.dart';
import '../../football/providers/football_providers.dart';
import '../data/lens_repository.dart';
import '../data/receipt_parser.dart';

// detectClubs tinggal di receipt_parser.dart; di-reexport supaya import lama
// (mis. test) tetap bekerja.
export '../data/receipt_parser.dart' show detectClubs;

class LensResult {
  const LensResult({
    required this.imagePath,
    required this.text,
    required this.draft,
    this.ratesFromCache = false,
  });

  final String imagePath;
  final String text;

  /// Hasil parsing struk/karcis: jenis, nominal, kategori, klub, tanggal, dan
  /// laga yang cocok. UI membangun kartu pengeluaran dari data ini.
  final ReceiptDraft draft;

  /// true bila konversi Rupiah memakai kurs dari cache Hive, bukan request baru.
  final bool ratesFromCache;
}

class LensNotifier extends StateNotifier<AsyncValue<LensResult?>> {
  LensNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;
  final _picker = ImagePicker();

  /// Pindai foto, lalu parse jadi [ReceiptDraft]. Pemindaian tetap jalan tanpa
  /// tim favorit; [clubs] dan [matches] hanya dipakai untuk mengenali klub/laga.
  Future<void> scan(ImageSource source, {DocKind? forceKind}) async {
    final x = await _picker.pickImage(
        source: source, maxWidth: 1600, imageQuality: 90);
    if (x == null) return;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final text = await _ref.read(lensRepositoryProvider).recognize(x.path);
      final clubs = _ref.read(clubsProvider).valueOrNull ?? const <PlClub>[];
      final matches = _ref.read(matchesProvider).valueOrNull?.data ??
          const <FootballMatch>[];

      // C2: `ratesProvider` sudah mengembalikan cache Hive saat offline, jadi
      // `null` di sini berarti benar-benar tidak ada kurs sama sekali.
      RatesSnapshot? snap;
      try {
        snap = await _ref.read(ratesProvider.future);
      } catch (_) {
        snap = null; // kartu tetap tampil, konversi diisi manual
      }

      return LensResult(
        imagePath: x.path,
        text: text,
        draft: parseReceipt(
          text,
          clubs: clubs,
          matches: matches,
          forceKind: forceKind,
        ),
        ratesFromCache: snap?.fromCache ?? false,
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
