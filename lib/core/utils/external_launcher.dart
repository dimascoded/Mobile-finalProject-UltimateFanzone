import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Membuka URI di aplikasi eksternal. Dapat diganti palsu di widget test.
typedef ExternalLauncher = Future<bool> Function(Uri uri);

final externalLauncherProvider = Provider<ExternalLauncher>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
