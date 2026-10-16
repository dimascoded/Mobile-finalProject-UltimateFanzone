import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_fanzone/features/away_day/data/away_day_repository.dart';
import 'package:ultimate_fanzone/features/gamification/data/blockchain.dart';

void main() {
  // C2: parse per-item toleran. Satu baris rusak tidak boleh menghapus data lain.
  group('AwayDayExpense.fromJson toleran', () {
    test('nomil hilang jadi 0, bukan exception', () {
      final e = AwayDayExpense.fromJson({
        'title': 'Tiket',
        'category': 'tiket',
        'date': '2026-03-01T10:00:00.000',
      });
      expect(e.amountGbp, 0);
      expect(e.amountIdr, 0);
      expect(e.title, 'Tiket');
    });

    test('nomil bertipe string angka tetap diterima', () {
      final e = AwayDayExpense.fromJson({
        'title': 'Tiket',
        'amountGbp': 45.5,
        'amountIdr': 880000,
        'category': 'tiket',
        'date': '2026-03-01T10:00:00.000',
      });
      expect(e.amountGbp, 45.5);
      expect(e.amountIdr, 880000);
    });

    test('judul kosong diganti placeholder', () {
      final e = AwayDayExpense.fromJson({
        'title': '   ',
        'amountGbp': 1,
        'amountIdr': 1,
        'category': 'tiket',
        'date': '2026-03-01T10:00:00.000',
      });
      expect(e.title, 'Tanpa judul');
    });

    test('kategori tidak dikenal jatuh ke lainnya', () {
      final e = AwayDayExpense.fromJson({
        'title': 'X',
        'amountGbp': 1,
        'amountIdr': 1,
        'category': 'nope',
        'date': '2026-03-01T10:00:00.000',
      });
      expect(e.category, AwayDayCategory.lainnya);
    });

    test('tanggal rusak tidak melempar', () {
      final e = AwayDayExpense.fromJson({
        'title': 'X',
        'amountGbp': 1,
        'amountIdr': 1,
        'category': 'tiket',
        'date': 'bukan tanggal',
      });
      expect(e.date.millisecondsSinceEpoch, 0);
    });

    test('round-trip toJson/fromJson mempertahankan nilai', () {
      final asli = AwayDayExpense(
        title: 'Merch scarf',
        amountGbp: 12.25,
        amountIdr: 232750,
        category: AwayDayCategory.merchandise,
        date: DateTime.utc(2026, 3, 1, 10),
        clubKey: 'arsenal',
      );
      final kembali = AwayDayExpense.fromJson(asli.toJson());
      expect(kembali.title, asli.title);
      expect(kembali.amountGbp, asli.amountGbp);
      expect(kembali.amountIdr, asli.amountIdr);
      expect(kembali.category, asli.category);
      expect(kembali.clubKey, 'arsenal');
    });
  });

  group('Block.fromJson toleran', () {
    test('index string angka diterima', () {
      final b = Block.fromJson({
        'index': 3,
        'timestamp': 1700000000,
        'type': 'stamp',
        'data': {'stadium': 'Emirates'},
        'prevHash': 'abc',
        'hash': 'def',
      });
      expect(b.index, 3);
      expect(b.data['stadium'], 'Emirates');
    });

    test('field hilang tidak melempar, hash kosong menandai tidak valid', () {
      final b = Block.fromJson({'data': {}});
      expect(b.index, 0);
      expect(b.hash, '');
      expect(b.type, 'unknown');
      expect(b.data, isEmpty);
    });

    test('data non-map menjadi map kosong', () {
      final b = Block.fromJson({'index': 1, 'data': 'bukan map'});
      expect(b.data, isEmpty);
    });

    test('block dengan hash kosong membuat rantai tidak valid', () {
      final rusak = Block.fromJson({'index': 1, 'data': {}});
      final chain = [Blockchain.genesis(), rusak];
      // Hash kosong tidak cocok dengan hash hasil hitung ulang, jadi rantai
      // ditolak alih-alih diterima diam-diam.
      expect(Blockchain.isValid(chain), isFalse);
    });

    test('block yang dihitung ulang tetap valid dalam rantai', () {
      final genesis = Blockchain.genesis();
      final chain = [
        genesis,
        Blockchain.next(
          [genesis],
          'stamp',
          {'stadium': 'Emirates', 'amountIdr': 1500.0},
          '0xabc',
        ),
      ];
      expect(Blockchain.isValid(chain), isTrue);
    });
  });
}
