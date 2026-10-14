import 'package:flutter_test/flutter_test.dart';
import 'package:smart_football_fan/features/away_day/data/away_day_repository.dart';
import 'package:smart_football_fan/features/football/data/models.dart';
import 'package:smart_football_fan/features/lens/data/receipt_parser.dart';

const _sample1 = 'THE PIE SHOP\n'
    '12 High Street, London E15 1AA\n'
    'Tel 020 7946 0958\n'
    '24/10/2026 13:42\n'
    'Chicken pie x2     11.00\n'
    'Coffee             3.50\n'
    'Subtotal           14.50\n'
    'VAT 20%            2.42\n'
    'TOTAL  £14.50\n'
    'Card **** 4242';

const _sample2 = 'WARUNG NASI BU TINI\n'
    'Jl. Melati No. 5\n'
    '12/10/2026 19:05\n'
    'Nasi Goreng      2   50.000\n'
    'Es Teh           2   10.000\n'
    'Subtotal              60.000\n'
    'PPN 10%                6.000\n'
    'Total Bayar           66.000\n'
    'Tunai                100.000\n'
    'Kembali               34.000';

const _sample3 = 'PREMIER LEAGUE\n'
    'EMIRATES STADIUM\n'
    'ARSENAL v CHELSEA\n'
    'Sat 24 Oct 2026  15:00\n'
    'Block 112  Row 14  Seat 9\n'
    'Gate B\n'
    'Ticket price £68.00';

const _arsenal = PlClub(
  key: 'arsenal',
  name: 'Arsenal FC',
  shortName: 'Arsenal',
  tla: 'ARS',
  city: 'London',
  stadium: 'Emirates Stadium',
  lat: 51.5549,
  lng: -0.1084,
  color: 0xFFEF0107,
  aliases: ['arsenal'],
);

const _chelsea = PlClub(
  key: 'chelsea',
  name: 'Chelsea FC',
  shortName: 'Chelsea',
  tla: 'CHE',
  city: 'London',
  stadium: 'Stamford Bridge',
  lat: 51.4817,
  lng: -0.1910,
  color: 0xFF034694,
  aliases: ['chelsea'],
);

void main() {
  const clubs = [_arsenal, _chelsea];

  group('sample 1: UK cafe receipt', () {
    final draft = parseReceipt(_sample1, clubs: clubs);

    test('kind receipt', () => expect(draft.kind, DocKind.receipt));
    test('currency GBP tanpa tebakan', () {
      expect(draft.currency, 'GBP');
      expect(draft.currencyGuessed, isFalse);
    });
    test('amount 14.50', () => expect(draft.amount, 14.50));
    test('category makanan',
        () => expect(draft.category, AwayDayCategory.makanan));
    test('title The Pie Shop', () => expect(draft.title, 'The Pie Shop'));
    test('documentDate 2026-10-24',
        () => expect(draft.documentDate, DateTime(2026, 10, 24)));
    test('TOTAL lebih tinggi dari Subtotal', () {
      expect(draft.candidates.first.line.toUpperCase(), contains('TOTAL'));
    });
  });

  group('sample 2: Indonesian struk', () {
    final draft = parseReceipt(_sample2, clubs: clubs);

    test('currency IDR dengan tebakan', () {
      expect(draft.currency, 'IDR');
      expect(draft.currencyGuessed, isTrue);
    });
    test('amount 66000', () => expect(draft.amount, 66000));
    test('category makanan',
        () => expect(draft.category, AwayDayCategory.makanan));
    test('title Warung Nasi Bu Tini',
        () => expect(draft.title, 'Warung Nasi Bu Tini'));
  });

  group('sample 3: match ticket', () {
    final match = FootballMatch(
      id: 555,
      kickoffUtc: DateTime.utc(2026, 10, 24, 15, 0),
      status: 'SCHEDULED',
      matchday: 9,
      homeName: 'Arsenal FC',
      awayName: 'Chelsea FC',
      homeShort: 'Arsenal',
      awayShort: 'Chelsea',
      homeTla: 'ARS',
      awayTla: 'CHE',
    );
    final draft = parseReceipt(_sample3, clubs: clubs, matches: [match]);

    test('kind ticket', () => expect(draft.kind, DocKind.ticket));
    test('klub berurutan', () {
      expect(draft.clubs.map((c) => c.shortName), ['Arsenal', 'Chelsea']);
    });
    test('amount 68.00 GBP', () {
      expect(draft.amount, 68.00);
      expect(draft.currency, 'GBP');
    });
    test('category tiket', () => expect(draft.category, AwayDayCategory.tiket));
    test('title Tiket Arsenal vs Chelsea',
        () => expect(draft.title, 'Tiket Arsenal vs Chelsea'));
    test('documentDate 2026-10-24',
        () => expect(draft.documentDate, DateTime(2026, 10, 24)));
    test('matchId cocok', () => expect(draft.matchId, 555));
    test('block/row/seat/waktu bukan kandidat', () {
      for (final bad in [112.0, 14.0, 9.0, 15.0]) {
        expect(
          draft.candidates.any((c) => c.amount == bad),
          isFalse,
          reason: '$bad tidak boleh jadi kandidat',
        );
      }
    });
  });

  test('tanpa simbol dan tanpa cue -> GBP dengan currencyGuessed', () {
    final draft = parseReceipt(
      'CORNER BAKERY\nSandwich 4.00\nTotal 4.00',
      clubs: const [],
    );
    expect(draft.currency, 'GBP');
    expect(draft.currencyGuessed, isTrue);
  });

  test('Change dan Cash tidak pernah dipilih', () {
    final draft = parseReceipt(
      'CAFE\nCoffee 3.00\nTotal £3.00\nChange £0.00\nCash £50.00',
      clubs: const [],
    );
    expect(draft.amount, 3.00);
    expect(draft.candidates.first.amount, 3.00);
    expect(draft.candidates.first.line.toUpperCase(), contains('TOTAL'));
  });

  test('forceKind menimpa deteksi otomatis', () {
    final asTicket = parseReceipt(
      _sample1,
      clubs: clubs,
      forceKind: DocKind.ticket,
    );
    expect(asTicket.kind, DocKind.ticket);

    final asReceipt = parseReceipt(
      _sample3,
      clubs: clubs,
      forceKind: DocKind.receipt,
    );
    expect(asReceipt.kind, DocKind.receipt);
  });

  test('teks kosong tidak crash dan amount null', () {
    final draft = parseReceipt('', clubs: clubs);
    expect(draft.kind, DocKind.receipt);
    expect(draft.amount, isNull);
    expect(draft.candidates, isEmpty);
    expect(draft.documentDate, isNull);
    expect(draft.matchId, isNull);
  });
}
