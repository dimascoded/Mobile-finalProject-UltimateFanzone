# Guideline Lanjutan — Smart Football Fan (Liga Inggris)

> Dokumen ini adalah **pegangan untuk melanjutkan proyek**: status terakhir, cara kerja kode,
> sisa pekerjaan (langkah 5–7), dan bahan laporan. Baca bagian 1–3 dulu sebelum mengubah kode.

---

## 1. Konsep Proyek (TEMA BARU: Smart Football Fan — Premier League)

> Tema lama "Smart Global Traveler" tidak bisa dipakai. Proyek dimigrasi bertahap ke **Smart Football Fan**:
> pendamping penggemar Liga Inggris di Indonesia. Kickoff Liga Inggris (waktu London) sering jatuh dini hari WIB,
> sehingga konversi waktu, pengingat, dan alarm menjadi inti aplikasi.

Aplikasi berporos pada **Tim Favorit** (1 dari 20 klub Premier League 2026–27). Fitur utama:

| Fitur | Fungsi |
|---|---|
| Match Center | Jadwal dengan jam kickoff **WIB/WITA/WIT/London**, filter, pencarian tim, klasemen, top skor |
| Kartu tim favorit | Laga berikutnya + countdown + label "Dini hari" |
| Pengingat kickoff *(Round C)* | Notifikasi lokal terjadwal |
| Pundit AI *(Round B)* | Gemini, diberi klasemen & hasil terakhir sebagai bahan |
| Lens *(Round B)* | OCR tiket/poster/harga → cocokkan klub, konversi £ → Rp |
| Away Day *(Round B)* | Kalkulator biaya nonton langsung di Inggris (GBP → Rp) |
| Nobar Finder & check-in *(Round B)* | Stadion/venue + GPS |
| Fan Passport *(Round B–C)* | Blockchain: stamp stadion/nobar + komitmen prediksi (commit–reveal) |
| Prediksi skor *(Round C)* | Poin saja, **tanpa taruhan** |
| Penalty Shootout *(Round C)* | Mini game memakai gyroscope & accelerometer |
| SOS | Tahan 3 detik / goyang HP; nomor darurat UK (999) |

**Klub musim 2026–27 (20):** Arsenal, Aston Villa, Bournemouth, Brentford, Brighton, Chelsea, **Coventry City**,
Crystal Palace, Everton, Fulham, **Hull City**, **Ipswich Town**, Leeds United, Liverpool, Manchester City,
Manchester United, Newcastle United, Nottingham Forest, Sunderland, Tottenham Hotspur.
(Naik: Coventry, Ipswich, Hull. Turun: West Ham, Burnley, Wolves.) Data: `assets/data/pl_clubs.json`.

⚠️ **Koordinat stadion di JSON adalah perkiraan** (akurasi ±100–300 m). Verifikasi tiap titik di Google Maps sebelum
presentasi, dan perbaiki bila perlu. Nama stadion (mis. hak penamaan) bisa berubah.

### Sumber data pertandingan
football-data.org (tier gratis, kode kompetisi `PL`): 10 req/menit, skor tertunda, ada klasemen & top skor,
tanpa data pemain/statistik. **Bukan live score.** Hasil di-cache 15 menit (Hive). Tanpa API key → **data contoh**
(banner merah). Ketentuan: tier gratis untuk penggunaan non-komersial/edukasi (cek syarat resmi).

---

## 2. Status terhadap Rubrik Tugas

Legenda: ✅ selesai di kode • ⚠️ sebagian • ❌ belum

| # | Kriteria | Status | Lokasi / catatan |
|---|---|---|---|
| 1 | Bahasa pemrograman mobile | ✅ | Flutter/Dart |
| 2 | Konsep proyek akhir | ✅ | Bagian 1 |
| 3 | Login terenkripsi (non-Firebase) + session | ✅ | `features/auth`. SHA-256 sebelum kirim; token + kedaluwarsa 7 hari di `flutter_secure_storage`; auto-login via `LockScreen` |
| 4 | Login biometrik | ✅ | `local_auth` — tombol di Login dan `LockScreen` |
| 5 | Penyimpanan lokal **dan online** | ⚠️ | Lokal ✅ (Hive). **Online ❌ → Langkah 6** |
| 6 | Web service / API | ✅ | API kurs (Dio), Gemini |
| 7 | LBS terkait tema | ✅ | Jarak & arah ke landmark; verifikasi stamp berbasis GPS |
| 8 | Bottom nav: profil (gambar), saran & kesan PAM, logout | ✅ | Foto profil via kamera/galeri; tab Saran = Kesan + Saran; logout ada konfirmasi |
| 9 | Konversi mata uang ≥ 3 | ✅ | 6 mata uang bawaan + mata uang negara tujuan (10 kode) |
| 10 | Konversi waktu WIB/WIT/WITA/London | ✅ | `core/utils/time_utils.dart`, perhitungan lokal + DST |
| 11 | ≥ 2 sensor | ✅ | Accelerometer, Gyroscope, Magnetometer (kompas), + GPS |
| 12 | AI (image processing) | ✅ | **Lens**: ML Kit OCR on-device |
| 13 | LLM | ✅ | Gemini (itinerary) — terpisah dari fitur AI di atas |
| 14 | Mini game | ✅ | Speed Tapper 15 detik; menang → blok achievement |
| 15 | Pencarian & pemilihan | ✅ | Cari negara; cari pengeluaran; pilih landmark/mata uang |
| 16 | Notifikasi | ✅ | SOS (lokal; tombol tahan 3 dtk & goyang HP). Pengingat agenda → opsional |
| 17 | Blockchain sederhana | ✅ | `gamification/data/blockchain.dart` (hash + PoW + validasi) + wallet Web3 |
| 18 | Laporan | ❌ | **Langkah 7** (bagian 9) |

**Status kompilasi:** `flutter analyze` bersih dan `flutter test` hijau (196 test). Rincian per butir ada di `DAFTAR_PERBAIKAN.md`.

### Cara menjalankan (C6)

Semua konfigurasi masuk lewat `--dart-define`, tidak ada secret yang di-hardcode:

| Key | Wajib? | Fungsi |
|---|---|---|
| `GEMINI_API_KEY` | ya untuk Pundit AI | Kunci Gemini. Kosong → Pundit menampilkan pesan jelas, bukan data contoh |
| `GEMINI_MODEL` | tidak | Default model Gemini; ganti bila model dihentikan Google |
| `FOOTBALL_API_KEY` | tidak | Kunci football-data.org v4. Kosong → data contoh + banner merah, notifikasi dimatikan |
| `BACKEND_URL` | tidak | URL server sinkronisasi. Kosong → login dan sinkronisasi mode lokal (mock) |

```bash
flutter pub get
flutter run \
  --dart-define=GEMINI_API_KEY=... \
  --dart-define=FOOTBALL_API_KEY=... \
  --dart-define=BACKEND_URL=https://server-anda   # opsional
```

Server sinkronisasi (butuh Node.js 22.5+):

```bash
cd server && npm install
cp .env.example .env        # isi JWT_SECRET, wajib
node --env-file=.env index.js
```

### Batasan yang diketahui (C6)

- API key Gemini ada di sisi klien. Untuk produksi, arahkan lewat proxy backend (butir B8 belum dikerjakan).
- Kurs dan data sepak bola bergantung API gratis: bisa terlambat atau dibatasi kuotanya.
- Hash blok memakai SHA-256 tanpa salt; memenuhi rubrik, bukan praktik produksi.
- Blockchain lokal tanpa jaringan atau konsensus; mode demo bisa melewati verifikasi GPS.
- Zona waktu AS/Australia memakai satu kota acuan (New York / Sydney).

---

## 2b. Peta Migrasi ke Smart Football Fan

**Round A ✅ (selesai di kode):** data 20 klub, klien API + cache Hive + data contoh, tim favorit, Match Center
(jadwal 4 zona waktu, klasemen, top skor), kartu tim favorit di Home, judul/ikon aplikasi diganti.
Selama migrasi, fitur lama masih berjalan dengan **Trip default = Inggris (GB)** sebagai konteks "Away Day".

**Round B ✅:** Expense → **Away Day** (default GBP, kategori, anggaran total); **Pundit AI** (klasemen + 5 hasil
terakhir, tanpa data contoh, badge cache); kompas & paspor memakai **stadion 20 klub** dari `pl_clubs.json` dengan stamp
check-in stadion; **Lens** OCR mencocokkan teks lewat `PlClub.isTeam` lalu membuka jadwal klub; harga £ → Rp memakai
kurs yang di-cache Hive; SOS lepas dari `Trip` dan memakai nomor darurat UK (999 / 112).

**Round C ✅:** pengingat kickoff (`zonedSchedule` + izin exact alarm yang diminta saat runtime), **prediksi skor
commit–reveal** (hash commit sebelum kickoff, reveal diverifikasi setelah laga; salt tetap lokal), **Penalty Shootout**
(arah = kemiringan, kekuatan = ayunan), notifikasi hasil akhir dengan batas usia 6 jam.

**Round D ✅:** `features/trip` dan `countries.json` sudah dihapus; backend sinkronisasi (`server/`) dengan
commit–reveal terverifikasi rantai; 196 test Flutter + 52 test server hijau. Sisa: uji manual di perangkat fisik
(`T4` di `DAFTAR_PERBAIKAN.md`) dan penulisan laporan.

**Aturan produk:** tidak ada odds/taruhan (ilegal di Indonesia). Logo klub opsional (hak cipta klub); tampilan utama
memakai nama, singkatan, dan warna klub.

---

## 3. Arsitektur

Feature-Driven Clean Architecture + Riverpod. Tiap fitur: `data/` → `providers/` → `presentation/`.

```text
lib/
 ┣ core/
 ┃ ┣ database/hive_service.dart      # satu Box<String> 'app_cache'; semua data = JSON string
 ┃ ┣ network/ dio_client.dart • connectivity_provider.dart
 ┃ ┣ theme/ app_theme.dart (terang+gelap) • theme_provider.dart
 ┃ ┣ widgets/ offline_banner • empty_state • permission_gate
 ┃ ┗ utils/ app_config • crypto_utils • time_utils • permission_rationale
 ┣ features/
 ┃ ┣ auth/            # login, session+expiry, biometrik, LockScreen
 ┃ ┣ football/        # klub PL, API football-data.org, tim favorit, Match Center  ← POROS BARU
 ┃ ┣ trip/            # (lama; default Inggris; akan dihapus di Round D)
 ┃ ┣ dashboard/       # bottom nav, Home, Profil(+foto), Saran&Kesan
 ┃ ┣ ai_itinerary/    # Gemini + cache per negara
 ┃ ┣ lens/            # OCR ML Kit + PriceParser
 ┃ ┣ ar_pointer/      # kompas landmark (GPS + magnetometer + accel + gyro)
 ┃ ┣ expense_tracker/ # kurs, jam dunia, pengeluaran per trip
 ┃ ┣ gamification/    # blockchain, wallet, paspor/stamp, mini game
 ┃ ┗ sos_emergency/   # tombol SOS, notifikasi, nomor darurat
 ┗ main.dart          # sessionProvider → LockScreen | LoginScreen
```

### Aturan wajib (dari guideline awal)
1. Widget **dilarang** memanggil `dio`, Hive, Geolocator, atau Gemini langsung — lewat Provider/Notifier.
2. Tangani async dengan `AsyncValue.when(data/loading/error)`.
3. Stream sensor/GPS memakai `autoDispose`.
4. Rahasia (API key, URL backend) lewat `--dart-define`, tidak di-hardcode.
5. Notifier `autoDispose` yang punya `await` harus cek `if (!mounted) return;` sebelum mengubah `state`
   (menghindari error saat pengguna menutup layar di tengah proses).

### Penyimpanan Hive (key di `app_cache`)
| Key | Isi |
|---|---|
| `active_trip` | JSON Trip aktif (lama) |
| `favorite_team` | Key klub favorit (mis. `arsenal`) |
| `fd_matches` / `fd_standings` / `fd_scorers` (+`_at`) | Cache respons football-data.org |
| `expenses` | Daftar pengeluaran (ada `countryId`) |
| `itinerary_<ID>` | Teks itinerary terakhir per negara (mode offline) |
| `passport_chain` | Daftar blok (blockchain) |
| `profile_photo_path` | Path foto profil di folder dokumen aplikasi |
| `pam_feedback` | `{kesan, saran}` |
| `theme_mode` | `system` / `light` / `dark` |
| `permission_rationale` | Daftar izin yang sudah dijelaskan |

Secure storage: `session_token`, `session_expiry`, `user_email`, `wallet_private_key`.

---

## 4. Cara Menjalankan

Lihat `README.md` (izin Android/iOS, `FlutterFragmentActivity`, minSdk 23, iOS 15.5).

```bash
flutter pub get && flutter analyze
flutter run --dart-define=GEMINI_API_KEY=KEY_ANDA
```
Tanpa `BACKEND_URL`, login berjalan **mode mock** (terima email/password apa pun yang tidak kosong).

---

## 5. Catatan Penting per Fitur

**Auth** — Hash SHA-256 tanpa salt (sesuai guideline). Di produksi server wajib hash ulang (bcrypt/argon2) dan HTTPS.
Sesi valid → `LockScreen` meminta biometrik; perangkat tanpa biometrik langsung masuk.

**Waktu** — `TimeUtils.zoneTime(utc, baseOffset, rule)`; rule `none|eu|us|au`. Logika DST sudah diverifikasi
terhadap tanggal peralihan 2026. WIB/WITA/WIT tetap (Indonesia tanpa DST).

**Lens** — OCR memakai skrip Latin. Harga angka (¥, ₩, ฿, RM, £, €, $) terbaca baik; teks Jepang/Korea/Thai/Arab
tidak diterjemahkan (di luar cakupan). Parser (`price_parser.dart`) menangani `1,234.56`, `1.234,56`,
dan mata uang tanpa pecahan (JPY/KRW). Hasil bergantung kualitas foto; uji dengan menu/struk nyata.

**Kompas** — `flutter_compass` (magnetometer). Heading bisa meleset di dekat logam; tampilkan peringatan kalibrasi
(angka 8) jika diperlukan. Panah = `bearing − heading`.

**Paspor / Blockchain** — Blok: `index | timestamp | type | data | owner | prevHash | nonce → SHA-256`.
PoW difficulty 3 (hash diawali `000`, rata-rata ±4000 percobaan, hampir instan). `Blockchain.isValid` memeriksa
hash, PoW, urutan index, dan tautan `prevHash`. Sudah diuji (versi Python identik): data diubah, blok dihapus,
dan hash dipalsukan semuanya terdeteksi.
- Stamp wajib ≤ **500 m** dari landmark (`stampRadiusMeters`). **Mode demo** melewati GPS dan menandai
  blok `gps_verified: false` — gunakan hanya saat presentasi dan **jelaskan di laporan**.
- Ini blockchain **lokal tunggal** (tanpa jaringan peer / konsensus). Tulis jujur di laporan sebagai
  "blockchain sederhana" yang mendemonstrasikan hash-chaining dan proof-of-work.
- Wallet Web3 (`web3dart`) dibuat sekali; alamatnya menjadi `owner` blok. Tidak ada transaksi on-chain.

**Mini game** — skor ≥ 10 dalam 15 detik → blok `achievement`.

---

## 6. SISA PEKERJAAN

### Langkah 5 — Home, SOS, Tema ✅ SELESAI (flutter analyze bersih sebelum langkah ini)
- [x] **Home dashboard**: `TripCard` + `HomeSummary` (kurs hari ini, pengeluaran vs anggaran, progres stamp) + menu fitur.
- [x] **SOS selalu terjangkau**: tombol melayang merah di Dashboard (`SosHoldButton`), **tahan 3 detik**; di layar SOS tombol besar yang sama.
- [x] **Goyang HP = SOS**: `shakeProvider` (accelerometer > 25 m/s², 2 hentakan < 1 detik, cooldown 5 dtk) → dialog konfirmasi (tidak kirim otomatis).
- [x] **Tema**: `ColorScheme` seed + **mode gelap** (tombol di AppBar, tersimpan di Hive), tombol min. 48dp.
- [x] **Banner offline** (`onlineProvider`, cek tiap 10 dtk) dan **empty state** (`EmptyState`) di Itinerary, Lens, Expense.
- [x] **Penjelasan izin**: `PermissionGate` (layar Kompas) dan `confirmPermission` (Paspor → lokasi, Lens → kamera), tampil sekali per jenis izin.
- [x] **Itinerary berbentuk JSON** → timeline per hari + total biaya; jika JSON tidak terbaca, tampil teks mentah (`ItineraryParser`).
- [ ] *Belum dikerjakan (opsional):* skeleton loading (saat ini `CircularProgressIndicator`), pengingat agenda via notifikasi terjadwal,
      font kustom, konversi total itinerary ke Rupiah.

Catatan:
- Goyang HP aktif selama Dashboard terbuka (accelerometer hemat daya, tetap `autoDispose`).
- Cek koneksi memakai `InternetAddress.lookup` (tanpa paket tambahan) — tidak berjalan di Flutter Web.
- Karena FAB SOS menutupi pojok kanan bawah, daftar Home diberi padding bawah 96dp.

### Langkah 6 — Backend & database online (wajib rubrik #5)
Aplikasi tetap **offline-first**: tulis ke Hive dulu, sinkronkan ke server saat online.

**Endpoint minimum**

| Method | Path | Body / respons |
|---|---|---|
| POST | `/auth/register` | `{email, password(hash SHA-256)}` → 201 |
| POST | `/auth/login` | `{email, password(hash)}` → `{token}` (200) — dipakai `AuthRepository` |
| POST | `/sync` | header `Authorization: Bearer <token>`; body `{trip, expenses[], chain[], feedback}` → 200 |
| GET | `/sync` | → data terakhir milik user (untuk pulih di perangkat baru) |

**Skema (MySQL/SQLite)**
```sql
users(id PK, email UNIQUE, password_hash, created_at)
trips(id PK, user_id FK, country_id, city, days, budget_idr)
expenses(id PK, user_id FK, country_id, title, amount_idr, created_at)
chain_blocks(user_id FK, idx, timestamp, type, data_json, owner, prev_hash, nonce, hash, PRIMARY KEY(user_id, idx))
feedback(user_id PK, kesan, saran)
```

**Kerangka server (Node/Express + SQLite)**
```js
// npm i express better-sqlite3 bcryptjs jsonwebtoken
const express = require('express'), bcrypt = require('bcryptjs'), jwt = require('jsonwebtoken');
const app = express(); app.use(express.json());
const SECRET = process.env.JWT_SECRET; // jangan hardcode
app.post('/auth/login', async (req, res) => {
  const u = db.prepare('SELECT * FROM users WHERE email=?').get(req.body.email);
  // password dari klien = SHA-256; di server di-hash LAGI dengan bcrypt
  if (!u || !(await bcrypt.compare(req.body.password, u.password_hash)))
    return res.status(401).json({ error: 'Email/password salah' });
  res.json({ token: jwt.sign({ uid: u.id }, SECRET, { expiresIn: '7d' }) });
});
```
**Sisi Flutter** yang perlu ditambah: `features/sync/data/sync_repository.dart` (Dio + header token dari secure
storage), `providers/sync_provider.dart` (`StateNotifier<AsyncValue<DateTime?>>`), tombol "Sinkronkan" di Profil,
dan **validasi `Blockchain.isValid` pada data yang diunduh** sebelum menimpa rantai lokal.
Hosting gratis untuk uji: Render / Railway / VPS kampus; untuk demo lokal gunakan IP laptop (bukan `localhost`).
Android emulator mengakses laptop lewat `10.0.2.2`.

### Langkah 7 — Pengujian & Laporan
**Unit test** (`test/`), semua logika murni sudah siap diuji tanpa emulator:
```dart
// test/time_utils_test.dart
test('London BST aktif 1 Juli', () {
  final t = TimeUtils.london(DateTime.utc(2026, 7, 1, 12));
  expect(t.hour, 13);
});
test('London GMT 1 Januari', () => expect(TimeUtils.london(DateTime.utc(2026,1,1,12)).hour, 12));
test('Sydney DST Januari = UTC+11', () => expect(TimeUtils.zoneTime(DateTime.utc(2026,1,15,0),10,'au').hour, 11));

// test/blockchain_test.dart
test('rantai valid lalu rusak jika data diubah', () {
  var chain = [Blockchain.genesis()];
  chain.add(Blockchain.next(chain, 'stamp', {'landmark': 'A'}, '0x1'));
  expect(Blockchain.isValid(chain), true);
  final b = chain[1];
  chain[1] = Block(index: b.index, timestamp: b.timestamp, type: b.type, data: {'landmark': 'PALSU'},
      owner: b.owner, prevHash: b.prevHash, nonce: b.nonce, hash: b.hash);
  expect(Blockchain.isValid(chain), false);
});

// test/price_parser_test.dart
test('JPY', () => expect(PriceParser.parse('1,200', 'JPY'), 1200));
test('EUR', () => expect(PriceParser.parse('1.234,56', 'EUR'), 1234.56));
test('USD', () => expect(PriceParser.parse('12.50', 'USD'), 12.5));
```
Hapus `test/widget_test.dart` bawaan `flutter create` (akan gagal karena `MyApp` berbeda).

---

## 7. Daftar Uji Manual (isi kolom "Hasil" → langsung jadi lembar evaluasi laporan)

| ID | Skenario | Langkah | Hasil yang diharapkan | Hasil | ✔ |
|---|---|---|---|---|---|
| T01 | Login berhasil | Isi email+password → Masuk | Masuk Dashboard | | |
| T02 | Login kosong | Kosongkan field | Snackbar error (mode mock) | | |
| T03 | Auto-login | Tutup & buka app | LockScreen muncul | | |
| T04 | Biometrik | Tempel jari | Masuk Dashboard | | |
| T05 | Biometrik gagal | Jari salah | Tetap di LockScreen | | |
| T06 | Logout | Tab Logout → Keluar | Kembali ke Login; sesi terhapus | | |
| T07 | Foto profil | Profil → ketuk avatar → Galeri | Foto tampil, tetap ada setelah restart | | |
| T08 | Saran & Kesan | Isi → Simpan → restart | Isian tetap ada | | |
| T09 | Cari negara | Ketik "jep" | Hanya Jepang | | |
| T10 | Mulai trip | Pilih Jepang, 5 hari | TripCard tampil, jam JST berjalan | | |
| T11 | Itinerary online | Buat Itinerary | Teks dari Gemini tampil | | |
| T12 | Itinerary offline | Matikan internet → Buat | Chip "Mode offline" + data terakhir | | |
| T13 | Konversi kurs | Isi 1.000.000 | Hasil JPY, default JPY dipilih | | |
| T14 | Jam dunia | Buka Expense | WIB/WITA/WIT/London + Tokyo | | |
| T15 | Pengeluaran | + Tambah → geser hapus | Total & anggaran berubah | | |
| T16 | Cari pengeluaran | Ketik kata kunci | Daftar terfilter | | |
| T17 | Lens | Foto menu berharga | Harga terdeteksi + ≈ Rp | | |
| T18 | Kompas | Putar HP | Panah berputar; sensor tampil | | |
| T19 | Stamp jauh dari landmark | Cap (mode demo off) | Gagal + jarak ditampilkan | | |
| T20 | Stamp mode demo | Aktifkan demo → Cap | Blok baru, tandai "mode demo" | | |
| T21 | Validasi rantai | Buka Paspor | "Rantai blok valid" | | |
| T22 | Game menang | Skor ≥ 10 | Blok achievement; terlihat di Profil | | |
| T23 | SOS | Tekan → Kirim | Notifikasi + koordinat; nomor darurat negara tampil | | |
| T25 | SOS tahan | Tahan tombol merah 3 dtk (lepas sebelum 3 dtk) | Terkirim hanya jika ditahan penuh | | |
| T26 | Goyang HP | Goyang kuat 2x | Dialog konfirmasi SOS | | |
| T27 | Mode gelap | Ketuk ikon bulan di AppBar | Tema berganti, tetap setelah restart | | |
| T28 | Banner offline | Matikan internet | Banner merah muncul ±10 dtk | | |
| T29 | Itinerary timeline | Buat itinerary | Kartu per hari + total biaya | | |
| T24 | Izin ditolak | Tolak lokasi | Pesan error jelas, app tidak crash | | |

---

## 8. Skrip Demo Presentasi (±8 menit)
1. Login biometrik → Dashboard (T03–T04).
2. Pilih **Jepang** lewat pencarian → TripCard + jam JST.
3. Itinerary Gemini → matikan Wi-Fi → buka ulang (cache offline).
4. Expense: kurs JPY, jam dunia, catat pengeluaran.
5. **Lens**: foto menu/label harga → konversi Rupiah.
6. Kompas Landmark (sebut tiga sensor).
7. Paspor: stamp **mode demo** (jujur: tidak sedang di Jepang) → tunjukkan rantai valid, jelaskan hash & PoW.
8. Main game → blok achievement → Profil.
9. SOS → notifikasi + nomor darurat.
10. (Setelah Langkah 6) Sinkronisasi ke server.

---

## 9. Kerangka Laporan (sesuai rubrik)

1. Cover • 2. Halaman pengesahan • 3. Daftar isi
4. **Landasan teori & tema**: Flutter, Riverpod, Clean Architecture, SHA-256, biometrik, Hive, REST API,
   LBS/GPS, sensor (accelerometer/gyroscope/magnetometer), OCR/ML Kit, LLM, blockchain (hash-chaining, PoW).
5. **Perancangan (RPL)**: kebutuhan fungsional & non-fungsional, use case diagram, activity diagram (login,
   buat trip, cap stamp), class/ER diagram (Trip, Expense, Block, User), perancangan antarmuka.
6. **Implementasi**: per fitur → tujuan, potongan kode inti, penjelasan baris penting, screenshot.
   File utama: `auth_repository.dart`, `time_utils.dart`, `price_parser.dart`, `blockchain.dart`,
   `gamification_providers.dart`, `away_day_providers.dart`.
7. **Lembar evaluasi pengujian**: tabel uji manual (bagian 7) + hasil unit test.
8. Kesimpulan & saran (cantumkan keterbatasan: blockchain lokal, OCR Latin, backend sederhana).
9. Daftar pustaka • Lampiran (tautan repositori, tangkapan layar tambahan).

---

## 10. Keterbatasan & Risiko (jujur di laporan)

- `flutter analyze` bersih dan test hijau; jalankan ulang setelah paket dinaikkan versinya karena bisa muncul
  peringatan baru.
- API key Gemini ada di aplikasi (dart-define) → produksi memakai proxy backend (B8 belum dikerjakan).
- Nama model Gemini bisa dihentikan Google: ganti lewat `--dart-define=GEMINI_MODEL=...`.
- API kurs `exchangerate-api.com` v4 gratis dan bisa berubah/dibatasi.
- Hash SHA-256 tanpa salt hanya memenuhi rubrik; bukan praktik terbaik produksi.
- Blockchain lokal: tidak ada jaringan/konsensus; mode demo dapat dipakai untuk melewati GPS.
- Kompas rentan gangguan magnet; OCR tergantung kualitas foto.
- Zona waktu AS/Australia memakai satu kota acuan (New York / Sydney).

---

## 11. Troubleshooting Umum

| Gejala | Penyebab / solusi |
|---|---|
| `flutter pub get` gagal konflik versi | Jalankan `flutter pub upgrade --major-versions`, atau longgarkan versi di `pubspec.yaml` |
| Biometrik error `no_fragment_activity` | `MainActivity` harus `FlutterFragmentActivity` |
| Kamera/galeri tidak terbuka | Izin `CAMERA` (Android) / `NSCameraUsageDescription` (iOS) belum ditambah |
| Build Android gagal di ML Kit | `minSdkVersion 23`; iOS `platform :ios, '15.5'` |
| Pundit AI selalu error | `GEMINI_API_KEY` belum diberikan lewat `--dart-define`, atau model sudah usang |
| Pengingat kickoff terlambat | Izin exact alarm belum diberikan; aplikasi memintanya saat start, periksa Pengaturan aplikasi |
| Notifikasi iOS tidak muncul saat aplikasi terbuka | `UNUserNotificationCenter.current().delegate` harus diset di `AppDelegate.swift` |
| Panah kompas tidak bergerak | Emulator tidak punya magnetometer — uji di HP fisik |
| Stamp selalu "terlalu jauh" | Wajar di luar negara tujuan; aktifkan **Mode demo** |
| `widget_test.dart` error | Hapus file itu |

---

## 12. Konteks untuk melanjutkan bersama asisten AI

Salin teks ini ke percakapan baru bersama zip/kode proyek:

> Proyek Flutter "Smart Football Fan" (Liga Inggris; Riverpod, Feature-Driven Clean Architecture; lihat
> GUIDELINE_LANJUTAN.md). Nama paket `smart_football_fan`, applicationId `com.smartfootballfan`.
> Batch 1–7 di `DAFTAR_PERBAIKAN.md` sudah selesai: backend sinkronisasi, notifikasi, penalty, commit–reveal,
> akun per pengguna, UI, dan kebersihan proyek. `flutter analyze` bersih, 196 test Flutter + 52 test server hijau.
> Sisa: uji manual di perangkat fisik (T4) dan penulisan laporan.
> Patuhi aturan di bagian 3 (widget tidak boleh memanggil dio/Hive langsung, autoDispose untuk stream, cek
> `mounted` di notifier autoDispose). Tidak ada fitur betting.
