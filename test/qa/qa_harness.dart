// QA harness: pompa layar pada ukuran/teks/tema tertentu tanpa menyentuh
// jaringan, Hive perangkat, secure storage, atau plugin.
//
// Semua provider yang dipakai layar-layar QA di-override di sini supaya
// hasilnya deterministik dan cepat. Gambar sengaja tidak tersedia: setiap
// `ScrimImage` harus jatuh ke fallback-nya (itu bagian dari yang diuji).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ultimate_fanzone/core/database/hive_service.dart';
import 'package:ultimate_fanzone/core/network/rates_provider.dart';
import 'package:ultimate_fanzone/core/theme/app_theme.dart';
import 'package:ultimate_fanzone/features/away_day/providers/away_day_providers.dart';
import 'package:ultimate_fanzone/features/football/data/football_repository.dart';
import 'package:ultimate_fanzone/features/football/data/models.dart';
import 'package:ultimate_fanzone/features/football/providers/football_providers.dart';
import 'package:ultimate_fanzone/features/football/providers/kickoff_reminder_provider.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';
import 'package:ultimate_fanzone/features/gamification/data/chain_repository.dart';
import 'package:ultimate_fanzone/features/gamification/providers/gamification_providers.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/data/penalty_rules.dart';
import 'package:ultimate_fanzone/features/penalty_shootout/providers/penalty_provider.dart';

/// Pompa [screen] pada [size] (logis), [textScale], dan [brightness] tertentu.
///
/// `devicePixelRatio` = 2.0 dan ukuran fisik = `size * 2.0` supaya hitungan
/// device-independent sama persis dengan yang diminta. `tester.view` di-reset
/// otomatis lewat `addTearDown`.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  List<Override> overrides = const <Override>[],
  double devicePixelRatio = 2.0,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = size * devicePixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: screen,
          ),
        ),
      ),
    ),
  );
}

/// Settle yang tidak pernah "hang": berhenti begitu tidak ada frame terjadwal,
/// dan paling lama [maxPumps] iterasi. Aman untuk layar dengan animasi terus
/// (mis. indikator loading) maupun timer.
Future<void> settleQa(WidgetTester tester, {int maxPumps = 30}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (!tester.binding.hasScheduledFrame) return;
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Ringkas error menjadi satu baris: pesan utama + lokasi widget penyebab
/// (`file.dart:line:col`) yang diambil dari blok "relevant error-causing
/// widget" bila Flutter menyertakannya.
String qaErrorSummary(Object error) {
  final String summary;
  final String full;
  if (error is FlutterErrorDetails) {
    summary = error.exceptionAsString().trim().split('\n').first.trim();
    full = error.toString();
  } else {
    full = error.toString();
    summary = full
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => full.trim());
  }

  final lines = full.split('\n').map((line) => line.trim()).toList();
  final marker = lines.indexWhere(
    (line) => line.toLowerCase().contains('relevant error-causing widget'),
  );
  final location = RegExp(r'\S+\.dart:\d+:\d+');
  String? widget;
  if (marker >= 0 && marker + 1 < lines.length) {
    widget = location.firstMatch(lines[marker + 1])?.group(0);
  }
  widget ??= location.firstMatch(full)?.group(0);
  return widget == null ? summary : '$summary | $widget';
}

/// Siapkan Hive cache di direktori sementara (beberapa provider membacanya).
Future<Directory> initQaHive(String label) async {
  final dir = await Directory.systemTemp.createTemp('sgt_qa_$label');
  Hive.init(dir.path);
  HiveService.cache = await Hive.openBox<String>('qa_${label}_box');
  return dir;
}

/// Tutup Hive dan hapus direktori sementara.
Future<void> disposeQaHive(Directory dir) async {
  await Hive.close();
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

// ---------------------------------------------------------------------------
// Data contoh
// ---------------------------------------------------------------------------

/// Klub contoh (hanya 3 supaya picker dan badge tetap ringkas).
final List<PlClub> qaClubs = <PlClub>[
  const PlClub(
    key: 'arsenal',
    name: 'Arsenal',
    shortName: 'Arsenal',
    tla: 'ARS',
    city: 'London',
    stadium: 'Emirates Stadium',
    lat: 51.5549,
    lng: -0.1084,
    color: 0xFFEF0107,
    aliases: <String>['arsenal'],
  ),
  const PlClub(
    key: 'chelsea',
    name: 'Chelsea',
    shortName: 'Chelsea',
    tla: 'CHE',
    city: 'London',
    stadium: 'Stamford Bridge',
    lat: 51.4817,
    lng: -0.191,
    color: 0xFF034694,
    aliases: <String>['chelsea'],
  ),
  const PlClub(
    key: 'manchester_city',
    name: 'Manchester City',
    shortName: 'Man City',
    tla: 'MCI',
    city: 'Manchester',
    stadium: 'Etihad Stadium',
    lat: 53.4831,
    lng: -2.2004,
    color: 0xFF6CABDD,
    aliases: <String>['man city', 'city'],
  ),
];

/// Rantai contoh: genesis + stamp & kartu untuk [qaClubs] bila [populated].
List<Block> qaChain({required bool populated}) {
  var chain = <Block>[Blockchain.genesis()];
  if (!populated) return chain;
  for (final club in qaClubs) {
    chain = <Block>[
      ...chain,
      Blockchain.next(
        chain,
        'stamp',
        <String, dynamic>{
          'club': club.key,
          'stadium': club.stadium,
          'gps_verified': true,
        },
        'qa-owner',
      ),
      Blockchain.next(
        chain,
        'card',
        <String, dynamic>{'source': 'stamp', 'ref': club.key},
        'qa-owner',
      ),
    ];
  }
  return chain;
}

/// Platform sensor palsu: mengembalikan stream kosong supaya layar yang
/// mendengarkan akselerometer (mis. penalti) tidak memanggil method channel.
class QaFakeSensorsPlatform extends SensorsPlatform {
  @override
  Stream<AccelerometerEvent> accelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      const Stream<AccelerometerEvent>.empty();

  @override
  Stream<GyroscopeEvent> gyroscopeEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      const Stream<GyroscopeEvent>.empty();

  @override
  Stream<UserAccelerometerEvent> userAccelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      const Stream<UserAccelerometerEvent>.empty();

  @override
  Stream<MagnetometerEvent> magnetometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) =>
      const Stream<MagnetometerEvent>.empty();
}

/// Pasang platform sensor palsu supaya tidak ada panggilan ke plugin.
void installQaFakeSensors() {
  SensorsPlatform.instance = QaFakeSensorsPlatform();
}

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

/// Repositori klub dalam memori (tidak menyentuh Hive perangkat).
class QaClubRepository extends ClubRepository {
  QaClubRepository(this.favorite);

  final String? favorite;

  @override
  String? favoriteKey() => favorite;

  @override
  Future<List<PlClub>> load() async => qaClubs;

  @override
  Future<void> saveFavorite(String key) async {}
}

/// Repositori rantai dalam memori.
class QaChainRepository extends ChainRepository {
  QaChainRepository(this.chain);

  final List<Block> chain;

  @override
  List<Block> load() => chain;

  @override
  Future<void> save(List<Block> next) async {}
}

/// Notifier refleks dengan state tetap supaya grid target tampil tanpa timer.
class QaReflexNotifier extends ReflexNotifier {
  QaReflexNotifier(super.ref) {
    state = const ReflexState(running: true, zone: KickZone.topLeft);
  }
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

/// Kumpulan override untuk semua provider yang layar QA butuhkan.
///
/// [favorite] menyalakan tim favorit (Arsenal), [populated] mengisi rantai
/// stamp/kartu. Tidak ada panggilan jaringan/plugin di jalur ini.
List<Override> qaOverrides({
  bool favorite = false,
  bool populated = false,
}) {
  final now = DateTime.now().toUtc();
  final matches = <FootballMatch>[
    FootballMatch(
      id: 1,
      kickoffUtc: now.add(const Duration(days: 2)),
      status: 'SCHEDULED',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Chelsea',
      homeShort: 'ARS',
      awayShort: 'CHE',
      homeTla: 'ARS',
      awayTla: 'CHE',
    ),
    FootballMatch(
      id: 2,
      kickoffUtc: now.subtract(const Duration(days: 3)),
      status: 'FINISHED',
      matchday: 1,
      homeName: 'Chelsea',
      awayName: 'Arsenal',
      homeShort: 'CHE',
      awayShort: 'ARS',
      homeTla: 'CHE',
      awayTla: 'ARS',
      homeScore: 1,
      awayScore: 2,
    ),
    FootballMatch(
      id: 3,
      kickoffUtc: now.subtract(const Duration(minutes: 30)),
      status: 'IN_PLAY',
      matchday: 1,
      homeName: 'Arsenal',
      awayName: 'Manchester City',
      homeShort: 'ARS',
      awayShort: 'MCI',
      homeTla: 'ARS',
      awayTla: 'MCI',
      homeScore: 1,
      awayScore: 0,
    ),
  ];

  return <Override>[
    clubsProvider.overrideWith((ref) async => qaClubs),
    clubRepositoryProvider.overrideWithValue(
      QaClubRepository(favorite ? 'arsenal' : null),
    ),
    favoriteKeyProvider.overrideWith(
      (ref) =>
          FavoriteTeamNotifier(QaClubRepository(favorite ? 'arsenal' : null)),
    ),
    favoriteClubProvider.overrideWithValue(favorite ? qaClubs.first : null),
    matchesProvider.overrideWith(
      (ref) async => FootballResult<List<FootballMatch>>(
        matches,
        DataSource.live,
        now,
      ),
    ),
    standingsProvider.overrideWith(
      (ref) async => FootballResult<List<StandingRow>>(
        const <StandingRow>[
          StandingRow(
            position: 1,
            teamName: 'Arsenal',
            teamShort: 'ARS',
            tla: 'ARS',
            played: 10,
            won: 8,
            draw: 1,
            lost: 1,
            goalDiff: 15,
            points: 25,
          ),
          StandingRow(
            position: 2,
            teamName: 'Manchester City',
            teamShort: 'MCI',
            tla: 'MCI',
            played: 10,
            won: 7,
            draw: 2,
            lost: 1,
            goalDiff: 12,
            points: 23,
          ),
          StandingRow(
            position: 3,
            teamName: 'Chelsea',
            teamShort: 'CHE',
            tla: 'CHE',
            played: 10,
            won: 6,
            draw: 1,
            lost: 3,
            goalDiff: 6,
            points: 19,
          ),
        ],
        DataSource.live,
        now,
      ),
    ),
    scorersProvider.overrideWith(
      (ref) async => FootballResult<List<ScorerRow>>(
        const <ScorerRow>[
          ScorerRow(
              player: 'Pemain A',
              teamName: 'Arsenal',
              teamShort: 'ARS',
              goals: 9),
          ScorerRow(
              player: 'Pemain B',
              teamName: 'Manchester City',
              teamShort: 'MCI',
              goals: 8),
          ScorerRow(
              player: 'Pemain C',
              teamName: 'Chelsea',
              teamShort: 'CHE',
              goals: 6),
        ],
        DataSource.live,
        now,
      ),
    ),
    clubCrestProvider.overrideWithValue(const <String, String>{}),
    chainProvider.overrideWith(
      (ref) => ChainNotifier(QaChainRepository(qaChain(populated: populated))),
    ),
    kickoffLeadsProvider.overrideWith((ref) => KickoffLeadsNotifier()),
    stampDistanceProvider.overrideWith((ref) => Future<int?>.value(null)),
    ratesProvider.overrideWith(
      (ref) async => RatesSnapshot(
        const <String, double>{'GBP': 0.00005, 'USD': 0.00004, 'EUR': 0.000046},
        now,
      ),
    ),
    worldClockProvider.overrideWith((ref) async* {
      yield <String, DateTime>{
        'UTC': now,
        'WIB': now.add(const Duration(hours: 7)),
        'WITA': now.add(const Duration(hours: 8)),
        'WIT': now.add(const Duration(hours: 9)),
        'London': now,
      };
    }),
    tickProvider.overrideWith((ref) => Stream<DateTime>.value(now)),
    penaltyProvider.overrideWith((ref) => PenaltyNotifier(ref)),
    reflexProvider.overrideWith((ref) => QaReflexNotifier(ref)),
  ];
}

/// Cetak peringatan (dipakai grup informasi, bukan kegagalan).
void qaWarn(String message) => debugPrint('[QA-TEXTSCALE] $message');
