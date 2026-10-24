import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/football/data/reminder_leads.dart';

void main() {
  group('normalizeLeads', () {
    test('membuang nol, negatif, dan lebih dari 7 hari', () {
      expect(normalizeLeads([0, -5, maxLeadMinutes + 1]), isEmpty);
      expect(normalizeLeads([30, 0, 15, -1, maxLeadMinutes + 1, 60]),
          [60, 30, 15]);
    });

    test('batas 7 hari persis masih diterima', () {
      expect(normalizeLeads([maxLeadMinutes]), [maxLeadMinutes]);
    });

    test('duplikat dibuang', () {
      expect(normalizeLeads([30, 30, 15, 30]), [30, 15]);
    });

    test('diurutkan menurun: pengingat paling awal di depan', () {
      expect(normalizeLeads([15, 1440, 60]), [1440, 60, 15]);
    });

    test('paling banyak tiga slot disimpan', () {
      expect(normalizeLeads([15, 30, 60, 120, 1440]), [1440, 120, 60]);
      expect(normalizeLeads([15, 30, 60, 120, 1440]).length, maxReminderSlots);
    });

    test('hasil kosong diizinkan (pengingat nonaktif)', () {
      expect(normalizeLeads([]), isEmpty);
      expect(normalizeLeads([0, -3, maxLeadMinutes + 1]), isEmpty);
    });
  });

  group('formatLead', () {
    test('15 menit', () => expect(formatLead(15), '15 menit'));
    test('1 jam', () => expect(formatLead(60), '1 jam'));
    test('1 jam 30 menit', () => expect(formatLead(90), '1 jam 30 menit'));
    test('1 hari', () => expect(formatLead(1440), '1 hari'));
    test('1 hari 1 jam', () => expect(formatLead(1500), '1 hari 1 jam'));
  });

  group('leadBody', () {
    test('di bawah sehari memakai "Mulai dalam"', () {
      expect(leadBody(15), 'Mulai dalam 15 menit');
      expect(leadBody(60), 'Mulai dalam 1 jam');
      expect(leadBody(90), 'Mulai dalam 1 jam 30 menit');
    });

    test('sehari ke atas memakai "Mulai ... lagi"', () {
      expect(leadBody(1440), 'Mulai 1 hari lagi');
      expect(leadBody(1500), 'Mulai 1 hari 1 jam lagi');
    });
  });

  group('leadFromInput', () {
    test('unit menit', () => expect(leadFromInput(45, 'menit'), 45));
    test('unit jam', () => expect(leadFromInput(2, 'jam'), 120));
    test('unit hari', () => expect(leadFromInput(1, 'hari'), 1440));
    test('unit tak dikenal menghasilkan 0', () {
      expect(leadFromInput(5, 'detik'), 0);
    });
  });

  group('leadFromDhm', () {
    test('(0,0,45)=45', () => expect(leadFromDhm(0, 0, 45), 45));
    test('(1,0,0)=1440', () => expect(leadFromDhm(1, 0, 0), 1440));
    test('(1,2,30)=1590', () => expect(leadFromDhm(1, 2, 30), 1590));
    test('(0,0,90)=90', () => expect(leadFromDhm(0, 0, 90), 90));
    test('negatives treated as 0', () {
      expect(leadFromDhm(-1, -2, -3), 0);
      expect(leadFromDhm(-1, 1, 30), 90);
    });
  });

  group('plannedReminders', () {
    final now = DateTime.utc(2026, 10, 16, 12);

    test('lead time tak terurut dinormalisasi, slot mengikuti hasilnya', () {
      final kickoff = now.add(const Duration(days: 3));
      final planned = plannedReminders(kickoff, [15, 1440, 60, 30], now);
      expect(planned.map((e) => e.$1), [0, 1, 2]);
      expect(planned.map((e) => e.$2), [1440, 60, 30]);
      expect(planned[0].$3, kickoff.subtract(const Duration(days: 1)));
      expect(planned[1].$3, kickoff.subtract(const Duration(minutes: 60)));
      expect(planned[2].$3, kickoff.subtract(const Duration(minutes: 30)));
    });

    test('waktu fire yang sudah lewat dilewati, nomor slot tetap stabil', () {
      // Kickoff 1 jam lagi: lead 1440 menit jatuh 23 jam lalu dan lead 60
      // menit jatuh tepat sekarang (bukan "setelah sekarang") -> keduanya
      // dibuang, tetapi slot lead 15 menit tetap 2 karena dihitung dari
      // posisi di daftar ternormalisasi.
      final kickoff = now.add(const Duration(hours: 1));
      final planned = plannedReminders(kickoff, [1440, 60, 15], now);
      expect(planned.length, 1);
      expect(planned.single.$1, 2);
      expect(planned.single.$2, 15);
      expect(planned.single.$3, kickoff.subtract(const Duration(minutes: 15)));
      expect(planned.single.$3.isAfter(now), isTrue);
    });

    test('semua waktu fire lewat -> kosong', () {
      final kickoff = now.add(const Duration(minutes: 10));
      expect(plannedReminders(kickoff, [15], now), isEmpty);
    });

    test('lead time kosong -> tidak ada pengingat', () {
      final kickoff = now.add(const Duration(days: 1));
      expect(plannedReminders(kickoff, [], now), isEmpty);
      expect(plannedReminders(kickoff, [0, -1, maxLeadMinutes + 1], now),
          isEmpty);
    });
  });
}
