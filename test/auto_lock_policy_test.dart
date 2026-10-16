import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/auth/domain/auto_lock_policy.dart';

void main() {
  final base = DateTime(2026, 1, 1, 12);

  group('AutoLockPolicy.shouldLock', () {
    test('tidak mengunci bila aplikasi tidak pernah dijeda', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: null,
          now: base.add(const Duration(minutes: 5)),
          biometricEnabled: true,
        ),
        isFalse,
      );
    });

    test('tidak mengunci sebelum ambang waktu', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: base,
          now: base.add(const Duration(seconds: 59)),
          biometricEnabled: true,
        ),
        isFalse,
      );
    });

    test('mengunci tepat pada ambang waktu', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: base,
          now: base.add(AutoLockPolicy.timeout),
          biometricEnabled: true,
        ),
        isTrue,
      );
    });

    test('mengunci setelah ambang waktu terlewat', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: base,
          now: base.add(const Duration(minutes: 10)),
          biometricEnabled: true,
        ),
        isTrue,
      );
    });

    test('tidak mengunci bila biometrik dimatikan', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: base,
          now: base.add(const Duration(minutes: 10)),
          biometricEnabled: false,
        ),
        isFalse,
      );
    });

    test('tidak mengunci bila sedang ditahan (kamera/prompt)', () {
      expect(
        AutoLockPolicy.shouldLock(
          pausedAt: base,
          now: base.add(const Duration(minutes: 10)),
          biometricEnabled: true,
          suspended: true,
        ),
        isFalse,
      );
    });
  });
}
