import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/stadium_pointer/presentation/stadium_pointer_screen.dart';

const _dialKey = ValueKey<String>('stadium-compass-dial');

Future<double> _pumpDialAtWidth(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: CompassDialTestWrapper(relativeBearing: 42, color: Colors.red),
      ),
    ),
  );

  return tester.getSize(find.byKey(_dialKey)).width;
}

void main() {
  testWidgets('diameter dial <= 190 dan <= 0.6 * lebar pada lebar 320',
      (tester) async {
    final diameter = await _pumpDialAtWidth(tester, 320);

    expect(diameter, lessThanOrEqualTo(190));
    expect(diameter, lessThanOrEqualTo(0.6 * 320));
  });

  testWidgets('diameter dial <= 190 dan <= 0.6 * lebar pada lebar 600',
      (tester) async {
    final diameter = await _pumpDialAtWidth(tester, 600);

    expect(diameter, lessThanOrEqualTo(190));
    expect(diameter, lessThanOrEqualTo(0.6 * 600));
  });
}
