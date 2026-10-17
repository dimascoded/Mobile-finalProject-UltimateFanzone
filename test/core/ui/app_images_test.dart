import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/ui/app_images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paths = <String>[
    AppImages.heroMalamLaga,
    AppImages.headerLaga,
    AppImages.headerSeru,
    AppImages.headerAlat,
    AppImages.bgLogin,
  ];

  test('every AppImages path exists in the asset bundle', () async {
    for (final path in paths) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: 'Empty asset: $path');
    }
  });
}
