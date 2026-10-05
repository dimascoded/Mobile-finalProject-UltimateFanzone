import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/football/data/models.dart';
import 'package:smart_football_fan/features/football/providers/result_notification_provider.dart';

void main() {
  FootballMatch mk({
    required int id,
    required int home,
    required int away,
    String status = 'FINISHED',
    DateTime? kickoff,
  }) =>
      FootballMatch(
        id: id,
        kickoffUtc: kickoff ?? DateTime.utc(2026, 8, 15, 14, 0),
        status: status,
        matchday: 1,
        homeName: 'Arsenal FC',
        awayName: 'Chelsea FC',
        homeShort: 'ARS',
        awayShort: 'CHE',
        homeScore: home,
        awayScore: away,
      );

  group('resultNotification', () {
    test('menyebut skor dan pemenang', () {
      final n = resultNotification(mk(id: 1, home: 2, away: 1));
      expect(n.title, 'ARS vs CHE selesai');
      expect(n.body, contains('2-1'));
      expect(n.body, contains('ARS'));
    });

    test('menyebut seri saat skor sama', () {
      final n = resultNotification(mk(id: 2, home: 1, away: 1));
      expect(n.body, contains('Seri'));
      expect(n.body, isNot(contains('ARS. ')));
    });

    test('pemenang tampil ketika away menang', () {
      final n = resultNotification(mk(id: 3, home: 0, away: 3));
      // Skor selalu ditulis home-away, jadi 0-3.
      expect(n.body, contains('0-3'));
      expect(n.body, contains('CHE'));
    });

    test('skor nol-nol tetap seri', () {
      final n = resultNotification(mk(id: 4, home: 0, away: 0));
      expect(n.body, contains('Seri'));
    });
  });

  group('kunci notifikasi', () {
    String key(int id) => '#$id;';

    test('token laga unik per match', () {
      expect(key(10), '#10;');
      expect(key(11), isNot(key(10)));
    });

    test('token selalu diakhiri titik koma agar bisa displit', () {
      for (final id in [1, 42, 7001]) {
        expect(key(id).endsWith(';'), isTrue);
      }
    });

    test('rangkaian token bisa dipecah kembali ke id yang sama', () {
      final blob = [key(1), key(2), key(3)].join();
      final ids = blob
          .split(';')
          .where((t) => t.isNotEmpty)
          .map((t) => int.parse(t.replaceAll('#', '')))
          .toList();
      expect(ids, [1, 2, 3]);
    });

    test('cek sederhana: contains menandai sudah dinotifikasi', () {
      final done = '${key(1)}${key(2)}';
      expect(done.contains(key(2)), isTrue);
      expect(done.contains(key(3)), isFalse);
    });
  });

  group('jadwal hasil akhir', () {
    test('asumsi durasi liga dan jeda notifikasi tetap', () {
      expect(assumedMatchMinutes, greaterThan(90));
      expect(resultNotifyAfterMinutes, greaterThan(0));
    });

    test('waktu notifikasi = kickoff + durasi + jeda', () {
      final kickoff = DateTime.utc(2026, 8, 15, 14, 0);
      final when = kickoff
          .add(const Duration(minutes: assumedMatchMinutes))
          .add(const Duration(minutes: resultNotifyAfterMinutes));
      expect(when.difference(kickoff).inMinutes,
          assumedMatchMinutes + resultNotifyAfterMinutes);
    });

    test('laga yang sudah lama selesai tidak dijadwalkan ulang', () {
      // kickoff 4 jam lalu -> waktu notifikasi sudah lewat
      final kickoff = DateTime.now().toUtc().subtract(const Duration(hours: 4));
      final when = kickoff.add(const Duration(
          minutes: assumedMatchMinutes + resultNotifyAfterMinutes));
      expect(when.isAfter(DateTime.now().toUtc()), isFalse);
    });

    test('laga yang baru akan main dijadwalkan', () {
      final kickoff = DateTime.now().toUtc().add(const Duration(hours: 2));
      final when = kickoff.add(const Duration(
          minutes: assumedMatchMinutes + resultNotifyAfterMinutes));
      expect(when.isAfter(DateTime.now().toUtc()), isTrue);
    });
  });

  test('laga yang belum selesai tidak punya skor notifikasi', () {
    final m = FootballMatch(
      id: 9,
      kickoffUtc: DateTime.utc(2026, 8, 15, 14, 0),
      status: 'TIMED',
      matchday: 1,
      homeName: 'Arsenal FC',
      awayName: 'Chelsea FC',
      homeShort: 'ARS',
      awayShort: 'CHE',
    );
    expect(m.isFinished, isFalse);
    expect(m.hasScore, isFalse);
  });
}
