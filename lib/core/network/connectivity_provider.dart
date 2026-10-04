import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> _hasInternet() async {
  try {
    final r = await InternetAddress.lookup('example.com').timeout(const Duration(seconds: 3));
    return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Cek koneksi tiap 10 detik (tanpa paket tambahan). true = online.
final onlineProvider = StreamProvider.autoDispose<bool>((ref) async* {
  while (true) {
    yield await _hasInternet();
    await Future.delayed(const Duration(seconds: 10));
  }
});
