# Lembar Uji Manual (T4) - Smart Football Fan

Lembar ini adalah bukti pengujian untuk laporan. Isi kolom **Hasil aktual** dan
**Bukti** setelah menjalankan setiap skenario di perangkat fisik. Emulator tidak
cukup untuk baris 5, 6, 7, dan 13 karena tidak punya magnetometer, akselerometer,
dan Getak.

| Keterangan | Isi |
|---|---|
| Perangkat | |
| Android / iOS + versi | |
| Tanggal uji | |
| Penuji | |
| Build yang diuji | |

---

## 1. Cara menjalankan

### Skenario A - tanpa backend (cukup untuk 14 dari 15 baris)

```bash
flutter pub get
flutter run
```

Tanpa `BACKEND_URL` login memakai mode lokal, tanpa `FOOTBALL_API_KEY` semua
data contoh (ada banner merah "DATA CONTOH"), tanpa `GEMINI_API_KEY` Pundit AI
menolak dengan pesan jelas. Semua itu yang diuji, bukan error.

### Skenario B - backend + pengingat cepat (diperlukan baris 7, 8, 10, 11, 12)

```bash
# 1. Server di PC (butuh Node.js 22.5+)
cd server
npm install
cp .env.example .env          # isi JWT_SECRET (wajib)
node --env-file=.env index.js
# cek http://localhost:3000/health

# 2. Alamat IP PC di jaringan Wi-Fi yang sama dengan HP
ipconfig                     # cari "IPv4 Address", contoh 192.168.1.5

# 3. Jalankan aplikasi dari PC
flutter run \
  --dart-define=BACKEND_URL=http://192.168.1.5:3000 \
  --dart-define=KICKOFF_REMINDER_MINUTES=2 \
  --dart-define=FOOTBALL_API_KEY=...
```

Catatan penting:

- `KICKOFF_REMINDER_MINUTES=2` hanya untuk uji. Nilai produksi 30 menit.
- Build debug mengizinkan HTTP ke IP lokal (`usesCleartextTraffic` hanya di
  `android/app/src/debug/AndroidManifest.xml`). Build rilis tetap menolak HTTP.
- Windows Firewall bisa memblokir port 3000. Izinkan `node.exe` di jaringan
  privat bila sinkronisasi selalu gagal.
- Di iOS, HTTP ke IP lokal diblokir ATS. Pakai tunnel HTTPS
  (`cloudflared tunnel --url http://localhost:3000`) atau tambahkan exception
  ATS untuk pengujian lokal.

---

## 2. Prasyarat

- [ ] Lokasi (GPS) perangkat menyala dan izin lokasi diberikan
- [ ] Biometrik aktif di perangkat (sidik jari / Face ID) dan sudah terdaftar
- [ ] Kamera dan galeri bisa dipakai
- [ ] Notifikasi tidak diblokir sistem untuk aplikasi ini
- [ ] Wi-Fi PC dan HP pada jaringan yang sama (untuk baris 10-12)
- [ ] Sudah daftar akun A dan akun B (baris 11-12 butuh dua akun berbeda)

---

## 3. Tabel hasil

| No | Fitur | Cara menguji | Hasil yang diharapkan | Hasil aktual | Bukti |
|---|---|---|---|---|---|
| 1 | Registrasi dan login | Skenario A. Tekan **Daftar** di layar login, isi email dan password, lalu masuk | Home terbuka dengan 4 tab: Home, Profil, Saran, Logout | | |
| 2 | Kunci biometrik | Skenario A. Tutup lalu buka aplikasi saat sesi sudah ada | Prompt biometrik muncul tiap aplikasi dibuka | | |
| 2b | Tombol biometrik | Di layar login tekan **Masuk dengan Biometrik** dengan jari yang salah / dibatalkan | Pesan "Autentikasi biometrik gagal." dalam bahasa Indonesia, bukan pesan sistem mentah | | |
| 3 | Tim favorit | Home → pilih klub di daftar | Semua fitur terisi: kartu klub di Home, daftar stadion, Lens, pengingat | | |
| 4 | Cap stamp mode demo | **Paspor Digital** → nyalakan **Mode demo** → **Cap stamp** | Stamp muncul dengan status "mode demo", blok rantai bertambah, kartu validitas naik | | |
| 4b | Cap stamp GPS ditolak | Matikan **Mode demo** di lokasi yang jauh dari stadion → **Cap stamp** | Ditolak dengan "Terlalu jauh untuk cap GPS", tidak ada stamp baru | | |
| 4c | Cap stamp di dekat stadion (opsional) | Jika sedang berada dalam 800 m dari stadion, ulangi dengan **Mode demo** mati | Stamp tersimpan dengan status "GPS terverifikasi" | | |
| 5 | Kompas Stadion | **Kompas Stadion** → pilih stadion → putar HP 90°, 180°, 270° | Jarak km tetap, arah berubah mengikuti arah sebenarnya; 0° = lurus ke depan | | |
| 6 | Penalty Shootout | **Penalty Shootout** → **Siap & Ayun**, miringkan HP ke kiri/kanan lalu ayunkan; ulangi 5 kali | Meter arah dan kekuatan berubah; penanda arah bergerak; hasil "GOL!", "Ditepis kiper", "Terlalu lemah", atau "Melebar"; akhir "Sesi selesai: n/5 gol, skor s" | | |
| 6b | Penalty tanpa sensor | Tombol **Tendang manual (tanpa ayun)** | Tendangan tetap jalan tanpa ayunan, berguna saat sensor tidak ada | | |
| 7 | Pengingat kickoff | Skenario B dengan `KICKOFF_REMINDER_MINUTES=2`. Pilih klub favorit, buka **Match Center**, tekan ikon lonceng **Atur pengingat kickoff** | Dialog izin exact alarm muncul di Android 12+; snackbar menyebut jumlah pengingat; notifikasi "Kickoff X vs Y - Mulai dalam 2 menit" tiba tepat waktu | | |
| 8 | Notifikasi hasil akhir | Jika ada laga yang selesai dalam 6 jam terakhir | Notifikasi hasil menyebut skor dan pemenang; untuk seri disebut "seri" | | |
| 9 | Izin notifikasi dicabut | Tolak izin notifikasi, ulangi langkah 7 | Pengingat tetap dijadwalkan (izin jadwal berbeda dari izin tampil), notifikasi tidak terlihat | | |
| 10 | Sinkronisasi satu akun | Skenario B. Catat pengeluaran di **Away Day**, buka tab **Profil** → **Sinkron** | "Sinkronisasi selesai ..." muncul beserta jumlah data terkirim; jam sinkron terakhir terisi | | |
| 11 | Isolasi dua akun | Di perangkat/HP kedua, login dengan akun B → **Sinkron** | Pengeluaran akun A tidak muncul di akun B | | |
| 12 | Data kembali utuh | Kembali ke akun A → **Sinkron** | Pengeluaran A masih ada, tidak tertimpa atau hilang setelah sesi B | | |
| 13 | Data hilang saat logout | Tekan tab **Logout**, lalu login ulang dengan akun yang sama | Pengeluaran, prediksi, rantai, dan foto profil hilang total; tema tetap | | |
| 14 | SOS tahan 3 detik | **SOS Darurat** → tahan tombol **SOS** 3 detik | Koordinat tampil + notifikasi lokal + kalimat "BELUM dikirim ke siapa pun"; nomor 999/112 terlihat | | |
| 14b | SOS goyang | Di Home, goyangkan HP 2x | Dialog konfirmasi muncul sebelum mengirim | | |
| 14c | SOS tanpa izin lokasi | Tolak izin lokasi → ulangi langkah 14 | Pesan "Izin lokasi ditolak, koordinat tidak bisa dibaca." | | |
| 15 | Mode offline | Matikan Wi-Fi dan data, tunggu 10 detik | Banner "Mode offline - menampilkan data tersimpan"; Match Center dan Away Day tetap menampilkan isi cache; Pundit memakai cache dengan badge peringatan | | |
| 16 | Tema gelap | Tekan ikon bulan/matahari di app bar Home | Semua layar berubah tema; tema bertahan setelah aplikasi ditutup dan dibuka lagi | | |
| 17 | Pundit AI (opsional) | Skenario B + `GEMINI_API_KEY`. **Pundit AI** → pilih klub → analisis | Tiga paragraf bahasa Indonesia, maksimal 200 kata; klasemen memuat posisi klub favorit; tanpa data contoh | | |
| 18 | Lens OCR (opsional) | **Lens (OCR Harga)** → **Galeri** → pilih foto bertuliskan nama klub dan harga (£) | Klub terdeteksi, harga diterjemahkan ke Rupiah, tombol "Lihat jadwal <klub>" bekerja | | |
| 19 | Tidak ada kunci API | Jalankan `flutter run` tanpa `--dart-define` sama sekali | Banner "DATA CONTOH - bukan jadwal resmi", pengingat dinonaktifkan, Pundit menolak dengan pesan jelas, tidak ada crash | | |

Setiap baris yang gagal harus ditulis apa gejalanya, bukan hanya "tidak bisa".

---

## 4. Cara mengisi

- **Hasil aktual**: isi `Lulus`, `Gagal`, atau `Skip`. Untuk `Gagal`, tulis
  gejalanya apa yang muncul di layar, bukan "tidak bisa".
- **Bukti**: nama file screenshot, misalnya `04b_stamp_gps_ditolak.png`.
  Simpan semua di satu folder agar bisa ditempel ke lampiran laporan.
- Baris `4c`, `8`, `17`, `18` boleh `Skip` bila memang tidak bisa dilakukan.
  Yang tidak boleh di-skip tanpa alasan adalah baris P0: 4, 4b, 7, 10, 14, 15, 16.

---

## 5. Keterbatasan yang harus dicatat jujur di laporan

- **Tidak ada pengiriman apa pun di SOS.** Aplikasi hanya membaca koordinat,
  menampilkan notifikasi lokal, dan menampilkan nomor 999/112. Tidak ada backend
  pengirim, jadi jangan menulis "terkirim".
- **Radius cap 800 m memakai koordinat stadion perkiraan**, bukan koordinat resmi
  gerbang stadion. Di luar radius itu GPS akan menolak walau berdiri di depan
  stadion; itulah sebabnya ada Mode demo.
- **Kompas dan penalty butuh sensor fisik.** Emulator tidak punya magnetometer
  maupun akselerometer, jadi uji di HP.
- **Blockchain lokal tanpa jaringan atau konsensus.** Rantai bisa diverifikasi
  (hash dan proof-of-work) tetapi tidak Consensus distributed.
- **Sinkronisasi butuh server yang menyala** dan HP serta PC pada jaringan yang
  sama.
- **Pengingat kickoff butuh data jadwal asli.** Tanpa `FOOTBALL_API_KEY` semua
  data contoh dan pengingat sengaja dinonaktifkan supaya tidak muncul jadwal
  palsu.
