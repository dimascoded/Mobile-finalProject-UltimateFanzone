import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../data/notification_service.dart';

class SosNotifier extends StateNotifier<AsyncValue<String?>> {
  SosNotifier() : super(const AsyncData(null));

  Future<void> trigger() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition();
      final msg = 'SOS! Lokasi: ${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}';
      await NotificationService.show('🚨 SOS Terkirim', msg);
      // TODO: kirim ke backend / kontak darurat lewat Dio di sini.
      return msg;
    });
    if (!mounted) return;
    state = result;
  }
}

final sosProvider = StateNotifierProvider<SosNotifier, AsyncValue<String?>>(
    (ref) => SosNotifier());
