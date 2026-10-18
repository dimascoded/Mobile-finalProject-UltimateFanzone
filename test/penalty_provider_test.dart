import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/data/penalty_rules.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/providers/penalty_provider.dart';

void main() {
  group('PenaltyNotifier motion flow', () {
    test('latches top-left aim and sweet power after a 400 ms aim', () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      harness.aimTopLeftFor400ms();
      harness.advance(const Duration(milliseconds: 200));
      harness.spike(15);
      expect(harness.state.phase, Phase.swinging);

      await harness.waitForSettle();

      expect(harness.state.last?.zone, KickZone.topLeft);
      expect(harness.state.last?.band, PowerBand.sweet);
    });

    test('a 3 m/s2 movement does not trigger a kick', () {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      harness.aimTopLeftFor400ms();
      harness.advance(const Duration(milliseconds: 200));
      harness.spike(3);

      expect(harness.state.phase, Phase.aiming);
      expect(harness.state.results, isEmpty);
    });

    test('a spike during the 600 ms cooldown does not kick', () {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      harness.emitResting();
      harness.advance(const Duration(milliseconds: 500));
      harness.spike(15);

      expect(harness.state.phase, Phase.aiming);
      expect(harness.state.results, isEmpty);
    });

    test('aim changes during the swing do not change the latched zone',
        () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      harness.aimTopLeftFor400ms();
      harness.advance(const Duration(milliseconds: 200));
      harness.spike(15);
      harness.emit(x: 4, y: 9.81, z: -2);
      expect(harness.state.zone, KickZone.topLeft);

      await harness.waitForSettle();

      expect(harness.state.last?.zone, KickZone.topLeft);
    });

    test('a peak above 16 resolves as too hard and over the bar', () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      harness.advance(const Duration(milliseconds: 600));
      harness.emitResting();
      harness.spike(18);
      await harness.waitForSettle();

      expect(harness.state.last?.band, PowerBand.tooHard);
      expect(harness.state.last?.outcome, ShotOutcome.overBar);
    });

    test('five over-bar attempts finish without minting a goal achievement',
        () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      for (var attempt = 0; attempt < PenaltyRules.attempts; attempt++) {
        harness.advance(const Duration(milliseconds: 600));
        harness.emitResting();
        harness.spike(18);
        await harness.waitForSettle();
        if (attempt < PenaltyRules.attempts - 1) harness.notifier.next();
      }

      expect(harness.state.phase, Phase.finished);
      expect(harness.state.taken, PenaltyRules.attempts);
      expect(harness.state.minted, isFalse);
    });

    test('flick uses its direction and speed to resolve a kick', () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);

      await harness.notifier.flick(dx: -1, dy: 1, speed: 0.75);

      expect(harness.state.phase, Phase.resolved);
      expect(harness.state.last?.zone, KickZone.topLeft);
      expect(harness.state.last?.band, PowerBand.sweet);
    });

    test('demo kick uses the selected zone', () async {
      final harness = _PenaltyHarness();
      addTearDown(harness.dispose);
      harness.controller.addError(StateError('sensor unavailable'));
      await Future<void>.delayed(Duration.zero);

      expect(harness.state.demo, isTrue);
      harness.notifier.selectZone(KickZone.topLeft);
      harness.notifier.demoKick();
      await harness.waitForSettle();

      expect(harness.state.last?.zone, KickZone.topLeft);
    });
  });
}

class _PenaltyHarness {
  _PenaltyHarness() {
    now = DateTime.utc(2026, 1, 1);
    controller = StreamController<AccelerometerEvent>.broadcast(sync: true);
    container = ProviderContainer(
      overrides: [
        penaltyProvider.overrideWith(
          (ref) => PenaltyNotifier(
            ref,
            accelerometer: () => controller.stream,
            clock: () => now,
          ),
        ),
      ],
    );
    container.listen(penaltyProvider, (_, __) {});
    notifier = container.read(penaltyProvider.notifier);
  }

  late DateTime now;
  late StreamController<AccelerometerEvent> controller;
  late ProviderContainer container;
  late PenaltyNotifier notifier;

  PenaltyState get state => container.read(penaltyProvider);

  void advance(Duration duration) => now = now.add(duration);

  void emit({double x = 0, double y = 9.81, double z = 0}) {
    controller.add(AccelerometerEvent(x, y, z));
  }

  void emitResting() => emit();

  void spike(double shake) => emit(x: 9.81 + shake, y: 0, z: 0);

  void aimTopLeftFor400ms() {
    emitResting();
    for (var sample = 0; sample < 8; sample++) {
      advance(const Duration(milliseconds: 50));
      emit(x: -4, y: 9.81, z: 2);
    }
  }

  Future<void> waitForSettle() =>
      Future<void>.delayed(const Duration(milliseconds: 380));

  Future<void> dispose() async {
    container.dispose();
    await controller.close();
  }
}
