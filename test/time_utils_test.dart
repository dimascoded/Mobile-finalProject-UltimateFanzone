import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/core/utils/time_utils.dart';

/// Zona waktu yang dipakai aplikasi, lengkap dengan aturan DST-nya.
///
/// Batas di bawah mengikuti aturan resmi zona tersebut untuk tahun 2026:
///   EU/London  : terakhir Minggu Maret 01:00 UTC s/d terakhir Minggu Oktober 01:00 UTC
///   US/New York: Minggu ke-2 Maret 07:00 UTC s/d Minggu ke-1 November 06:00 UTC
///   AU/Sydney  : Minggu ke-1 Oktober 16:00 UTC s/d Minggu ke-1 April 03:00
///                waktu lokal (= 16:00 UTC hari sebelumnya)
void main() {
  DateTime u(int y, int m, int d, [int h = 0, int min = 0, int sec = 0]) =>
      DateTime.utc(y, m, d, h, min, sec);

  group('DST Eropa (London)', () {
    test('29 Mar 2026: sebelum 01:00 UTC masih GMT, sesudahnya BST', () {
      expect(TimeUtils.isDst(u(2026, 3, 29, 0), 'eu'), isFalse);
      expect(TimeUtils.isDst(u(2026, 3, 29, 1), 'eu'), isTrue);
    });

    test('london memakai offset +1 saat DST', () {
      expect(TimeUtils.london(u(2026, 3, 29, 0)), u(2026, 3, 29, 0));
      expect(TimeUtils.london(u(2026, 3, 29, 1)), u(2026, 3, 29, 2));
      expect(TimeUtils.london(u(2026, 7, 1, 12)), u(2026, 7, 1, 13));
    });

    test('25 Okt 2026: 00:59 UTC masih BST, 01:00 UTC sudah GMT', () {
      expect(TimeUtils.isDst(u(2026, 10, 25, 0), 'eu'), isTrue);
      expect(TimeUtils.isDst(u(2026, 10, 25, 1), 'eu'), isFalse);
    });

    test('malam 25 Okt 2026 pukul 01:30 GMT dihitung 01:30 lokal', () {
      // 00:30 UTC = 01:30 BST. Setelah jam mundur, 01:30 UTC = 01:30 GMT.
      // Angka jam lokal sama, jadi pengingat tidak boleh dijadwalkan ulang
      // hanya karena perl lintas batas DST.
      final t = u(2026, 10, 25, 1, 30);
      expect(TimeUtils.isDst(t, 'eu'), isFalse);
      expect(TimeUtils.london(t), u(2026, 10, 25, 1, 30));
    });

    test('Januari tanpa DST, Juli dengan DST', () {
      expect(TimeUtils.isDst(u(2026, 1, 15, 12), 'eu'), isFalse);
      expect(TimeUtils.isDst(u(2026, 7, 15, 12), 'eu'), isTrue);
    });

    test('london menghasilkan jam sipil Inggris di batas DST', () {
      // Spring forward: 01:00 UTC 29 Mar langsung melompat ke 02:00 BST.
      expect(TimeUtils.london(u(2026, 3, 29, 0, 59)), u(2026, 3, 29, 0, 59));
      expect(TimeUtils.london(u(2026, 3, 29, 1, 0)), u(2026, 3, 29, 2, 0));
      // Masih BST sehari sebelum fall back.
      expect(TimeUtils.london(u(2026, 10, 24, 12)), u(2026, 10, 24, 13));
      // Fall back: 01:00 UTC 25 Okt sudah GMT, jadi 01:00 lokal.
      expect(TimeUtils.london(u(2026, 10, 25, 1)), u(2026, 10, 25, 1));
      // Musim dingin tanpa DST.
      expect(TimeUtils.london(u(2026, 12, 1, 12)), u(2026, 12, 1, 12));
    });
  });

  group('DST Amerika (New York, offset dasar -5)', () {
    test('8 Mar 2026 pukul 07:00 UTC mulai EDT', () {
      expect(TimeUtils.isDst(u(2026, 3, 8, 6), 'us'), isFalse);
      expect(TimeUtils.isDst(u(2026, 3, 8, 7), 'us'), isTrue);
    });

    test('1 Nov 2026 pukul 06:00 UTC kembali EST', () {
      expect(TimeUtils.isDst(u(2026, 11, 1, 5), 'us'), isTrue);
      expect(TimeUtils.isDst(u(2026, 11, 1, 6), 'us'), isFalse);
    });

    test('offset -4 saat EDT dan -5 saat EST', () {
      const ny = -5;
      expect(TimeUtils.zoneTime(u(2026, 3, 8, 12), ny, 'us'), u(2026, 3, 8, 8));
      expect(TimeUtils.zoneTime(u(2026, 1, 8, 12), ny, 'us'), u(2026, 1, 8, 7));
    });
  });

  group('DST Australia (Sydney, offset dasar +10)', () {
    test('3 Okt 2026 16:00 UTC mulai DST (belahan selatan)', () {
      expect(TimeUtils.isDst(u(2026, 10, 3, 15), 'au'), isFalse);
      expect(TimeUtils.isDst(u(2026, 10, 3, 16), 'au'), isTrue);
    });

    test('4 Apr 2026 16:00 UTC selesai DST (3:00 AEDT czas Sydney)', () {
      // DST Sydney berakhir Minggu pertama April pukul 03:00 waktu lokal,
      // yaitu 16:00 UTC hari sebelumnya.
      expect(TimeUtils.isDst(u(2026, 4, 4, 15, 59), 'au'), isTrue);
      expect(TimeUtils.isDst(u(2026, 4, 4, 16), 'au'), isFalse);
    });

    test('offset +11 saat DST dan +10 saat waktu standar', () {
      const syd = 10;
      expect(
          TimeUtils.zoneTime(u(2026, 1, 15, 0), syd, 'au'), u(2026, 1, 15, 11));
      expect(
          TimeUtils.zoneTime(u(2026, 7, 15, 0), syd, 'au'), u(2026, 7, 15, 10));
    });

    test('DST Sydney berlawanan dengan London di bulan yang sama', () {
      // Juli: London masih DST, Sydney sudah tidak. Karena itu tabel jam dunia
      // butuh dua aturan, bukan satu offset global.
      expect(TimeUtils.isDst(u(2026, 7, 1, 12), 'eu'), isTrue);
      expect(TimeUtils.isDst(u(2026, 7, 1, 12), 'au'), isFalse);
    });
  });

  group('Zona Indonesia tidak pernah DST', () {
    test('WIB, WITA, WIT tetap +7/+8/+9 sepanjang tahun', () {
      for (final m in [1, 4, 7, 10]) {
        expect(TimeUtils.wib(u(2026, m, 15, 3)), u(2026, m, 15, 10));
        expect(TimeUtils.wita(u(2026, m, 15, 3)), u(2026, m, 15, 11));
        expect(TimeUtils.wit(u(2026, m, 15, 3)), u(2026, m, 15, 12));
      }
    });

    test('rule none tidak pernah menghasilkan DST', () {
      expect(TimeUtils.isDst(u(2026, 3, 29, 1), 'none'), isFalse);
      expect(
          TimeUtils.zoneTime(u(2026, 3, 29, 1), 7, 'none'), u(2026, 3, 29, 8));
    });
  });

  group('Perubahan offset terjadi tepat di detik pertama', () {
    test('satu detik sebelum batas masih aturan lama', () {
      expect(TimeUtils.isDst(u(2026, 3, 28, 23, 59, 59), 'eu'), isFalse);
      expect(TimeUtils.isDst(u(2026, 3, 29, 1, 0, 0), 'eu'), isTrue);
      expect(TimeUtils.isDst(u(2026, 3, 8, 6, 59, 59), 'us'), isFalse);
      expect(TimeUtils.isDst(u(2026, 3, 8, 7, 0, 0), 'us'), isTrue);
      expect(TimeUtils.isDst(u(2026, 10, 3, 15, 59, 59), 'au'), isFalse);
      expect(TimeUtils.isDst(u(2026, 10, 3, 16, 0, 0), 'au'), isTrue);
    });

    test('huruf rule tidak dikenal menghasilkan false, bukan exception', () {
      expect(TimeUtils.isDst(u(2026, 7, 1, 12), 'xx'), isFalse);
    });
  });

  group('Pembantu tanggal', () {
    test('lastSunday menemukan Minggu terakhir bulan', () {
      // Maret 2026: Minggu tanggal 1, 8, 15, 22, 29.
      expect(TimeUtils.lastSunday(2026, 3), u(2026, 3, 29));
      // Oktober 2026: 4, 11, 18, 25. Minggu tanggal 1 November milik bulan
      // berikutnya, jadi bukan yang terakhir di Oktober.
      expect(TimeUtils.lastSunday(2026, 10), u(2026, 10, 25));
      // Februari 2026 hanya 28 hari, jadi Minggu terakhirnya tanggal 22.
      expect(TimeUtils.lastSunday(2026, 2), u(2026, 2, 22));
    });

    test('nthSunday menemukan Minggu ke-n', () {
      expect(TimeUtils.nthSunday(2026, 3, 1), u(2026, 3, 1));
      expect(TimeUtils.nthSunday(2026, 3, 2), u(2026, 3, 8));
      expect(TimeUtils.nthSunday(2026, 11, 1), u(2026, 11, 1));
    });
  });

  group('Format tampilan', () {
    test('formatDate memakai nama hari dan bulan berbahasa Indonesia', () {
      expect(TimeUtils.formatDate(u(2026, 10, 4, 12)), 'Min, 04 Okt');
      expect(TimeUtils.formatDate(u(2026, 10, 6, 12)), 'Sel, 06 Okt');
    });

    test('formatHm memakai nol di depan', () {
      expect(TimeUtils.formatHm(u(2026, 10, 4, 4, 5)), '04:05');
      expect(TimeUtils.formatHm(u(2026, 10, 4, 23, 59)), '23:59');
    });

    test('format memakai detik untuk hitung mundur', () {
      expect(TimeUtils.format(u(2026, 10, 4, 7, 8, 9)), '07:08:09');
    });

    test('countdown lebih dari sehari memakai jam dan menit', () {
      expect(
        TimeUtils.formatCountdown(
            const Duration(days: 2, hours: 3, minutes: 15)),
        '2 hr 03 j 15 m',
      );
    });

    test('countdown di bawah sehari memakai hh:mm:ss', () {
      expect(
          TimeUtils.formatCountdown(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
    });

    test('waktu yang sudah lewat dibaca "Sudah dimulai", bukan angka minus',
        () {
      expect(TimeUtils.formatCountdown(const Duration(seconds: -30)),
          'Sudah dimulai');
      expect(TimeUtils.formatCountdown(Duration.zero), '00:00:00');
    });
  });
}
