import 'package:flutter_test/flutter_test.dart';
import 'package:premiere_league_fan_assistant/features/away_day/presentation/away_day_screen.dart';
import 'package:premiere_league_fan_assistant/features/football/data/models.dart';
import 'package:premiere_league_fan_assistant/features/lens/providers/lens_provider.dart';

PlClub _club({
  required String key,
  required String name,
  required String shortName,
  required String tla,
  required List<String> aliases,
}) =>
    PlClub(
      key: key,
      name: name,
      shortName: shortName,
      tla: tla,
      city: 'Kota',
      stadium: 'Stadion',
      lat: 0,
      lng: 0,
      color: 0xFF000000,
      aliases: aliases,
    );

void main() {
  // UI4: keyboard Indonesia mengirim koma sebagai desimal.
  group('parseAmount', () {
    test('koma desimal dibaca sebagai pecahan', () {
      expect(parseAmount('45,50'), 45.5);
      expect(parseAmount('0,5'), 0.5);
    });

    test('titik tetap diterima', () {
      expect(parseAmount('45.50'), 45.5);
    });

    test('spasi dan spasi ribuan tidak merusak nilai', () {
      expect(parseAmount(' 1 234.50 '), 1234.5);
    });

    test('input kosong menghasilkan null', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('   '), isNull);
    });

    test('teks non angka menghasilkan null, bukan nol', () {
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('12abc'), isNull);
    });

    test('angka negatif ditolak oleh validasi, bukan oleh parser', () {
      // Parser hanya mengubah format; pengecekan "harus > 0" ada di validate.
      expect(parseAmount('-5'), -5);
    });

    test('koma dan titik bersamaan ditolak, bukan diam-diam ditafsirkan', () {
      expect(parseAmount('1.234,56'), isNull);
      expect(parseAmount('1,234.56'), isNull);
    });
  });

  // UI7: hasil OCR harus dicocokkan ke klub pakai PlClub.isTeam.
  group('detectClubs', () {
    final clubs = [
      _club(
        key: 'arsenal',
        name: 'Arsenal',
        shortName: 'Arsenal',
        tla: 'ARS',
        aliases: ['arsenal'],
      ),
      _club(
        key: 'man-city',
        name: 'Manchester City',
        shortName: 'Man City',
        tla: 'MCI',
        aliases: ['manchester city', 'man city', 'city'],
      ),
    ];

    test('mencocokkan nama lengkap', () {
      final found = detectClubs('Welcome to ARSENAL Emirates Stadium', clubs);
      expect(found.map((c) => c.key), ['arsenal']);
    });

    test('mencocokkan TLA', () {
      final found = detectClubs('MCI', clubs);
      expect(found.map((c) => c.key), ['man-city']);
    });

    test('mencocokkan nama pendek', () {
      final found = detectClubs('Season ticket: Man City', clubs);
      expect(found.map((c) => c.key), ['man-city']);
    });

    test('beberapa klub dalam satu teks terdeteksi', () {
      final found = detectClubs('ARS vs MCI', clubs);
      expect(found.map((c) => c.key), ['arsenal', 'man-city']);
    });

    test('klub tidak diulang walau muncul di beberapa baris', () {
      final found = detectClubs('Arsenal\nARSENAL\narsenal', clubs);
      expect(found.length, 1);
    });

    test('teks tanpa nama klub menghasilkan daftar kosong', () {
      expect(detectClubs('TOTAL 45.50 GBP', clubs), isEmpty);
    });

    test('baris kosong diabaikan', () {
      expect(detectClubs('\n\n   \n', clubs), isEmpty);
    });
  });
}
