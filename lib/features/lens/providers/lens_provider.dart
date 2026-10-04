import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/rates_provider.dart';
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
  });
  final String imagePath, text, currency;
  final List<LensPrice> prices;
}

class LensNotifier extends StateNotifier<AsyncValue<LensResult?>> {
  LensNotifier(this._ref) : super(const AsyncData(null));
  final Ref _ref;
  final _picker = ImagePicker();

  Future<void> scan(ImageSource source) async {
    final club = _ref.read(favoriteClubProvider);
    const currency = 'GBP';
    if (club == null) {
      state = AsyncError(Exception('Pilih tim favorit dulu'), StackTrace.current);
      return;
    }
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 90);
    if (x == null) return;

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final text = await _ref.read(lensRepositoryProvider).recognize(x.path);
      final found = PriceParser.extract(text, currency);

      Map<String, double>? rates;
      try {
        rates = await _ref.read(ratesProvider.future);
      } catch (_) {
        rates = null; // offline: tetap tampilkan harga mentah
      }
      final rate = rates?['GBP'] ?? rates?['GBP'];
      return LensResult(
        imagePath: x.path,
        text: text,
        currency: currency,
        prices: [
          for (final p in found)
            LensPrice(p.line, p.amount, rate == null || rate == 0 ? null : p.amount / rate),
        ],
      );
    });
    if (!mounted) return;
    state = result;
  }
}

final lensProvider = StateNotifierProvider.autoDispose<LensNotifier, AsyncValue<LensResult?>>(
    (ref) => LensNotifier(ref));
