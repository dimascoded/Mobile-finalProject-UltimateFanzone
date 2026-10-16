# Daftar Perbaikan — Ultimate Fanzone

Dokumen ini hanya berisi **pekerjaan yang perlu dilakukan**, diurutkan per batch.
Setiap butir punya: file yang diubah, langkah perbaikan, dan kriteria "selesai bila".

**Legenda**
- Prioritas: **P0** fitur tidak berfungsi / berisiko saat demo • **P1** penting • **P2** perbaikan kualitas
- Usaha: **S** < 1 jam • **M** 1–3 jam • **L** > 3 jam
- Tag **(terbukti)** = sudah dibuktikan dengan menjalankan backend; selebihnya berasal dari pembacaan kode, jadi
  verifikasi di perangkat tetap perlu.

**Aturan setelah setiap batch:** jalankan `flutter analyze`, `flutter test`, dan `cd server && npm test`
(semua harus hijau) sebelum lanjut ke batch berikutnya.

---

## Batch 1 — Demo-critical (kerjakan dulu)

- [ ] **F1 · Tombol cap stamp tidak ada** — P0 · M
  - File: `gamification/presentation/passport_screen.dart` (+ opsional `stadium_pointer_screen.dart`)
  - Perbaikan:
    - Tambahkan kartu stadion klub favorit dengan jarak ke stadion dan tombol **Cap stamp**
      yang memanggil `ref.read(stampProvider.notifier).stamp(club)`.
    - Tambahkan `SwitchListTile` **Mode demo** yang membaca/menulis `demoModeProvider`.
    - Tampilkan hasil/galat lewat `ref.listen(stampProvider, …)` (SnackBar).
    - Panggil `confirmPermission(...)` untuk izin lokasi sebelum stamp (kecuali mode demo).
  - Selesai bila: stamp bisa dicetak (mode demo dan GPS), jumlah di Profil dan `FanSummary` bertambah,
    stamp ganda ditolak, `chainValidProvider` tetap valid.

- [ ] **F2 · Model Gemini default sudah mati** — P0 · S
  - File: `core/utils/app_config.dart`, `pundit/data/pundit_repository.dart`
  - Perbaikan:
    - Hapus default `gemini-1.5-flash` (semua model 1.x/1.5 sudah retired → 404). Cek nama model aktif di
      `https://ai.google.dev/gemini-api/docs/models`; jangan hardcode model yang jadwal shutdown-nya dekat
      (gemini-2.5-flash dijadwalkan berhenti 16 Okt 2026).
    - Jadikan `GEMINI_MODEL` wajib lewat `--dart-define`, atau beri default model aktif + dokumentasikan di README.
    - Tangkap `GenerativeAIException`/404 dan tampilkan pesan: "Model tidak tersedia, perbarui GEMINI_MODEL".
  - Selesai bila: Pundit AI menghasilkan teks dengan model aktif; model salah menampilkan pesan yang jelas (bukan `Error: $e`).

- [ ] **F3 · SOS mengaku "Terkirim" padahal tidak** — P0 · S–M
  - File: `sos_emergency/providers/sos_provider.dart`, `sos_screen.dart`
  - Perbaikan (pilih salah satu):
    - Jujur: ubah judul notifikasi/snackbar menjadi "Lokasi ditampilkan di perangkat ini (belum dikirim ke siapa pun)".
    - Kirim sungguhan: tambahkan paket `share_plus`/`url_launcher`, simpan satu kontak darurat di Hive, buka
      `sms:`/WhatsApp dengan koordinat + tautan peta.
    - Tangani `isLocationServiceEnabled`, izin ditolak, dan beri `timeLimit` pada `getCurrentPosition`.
  - Selesai bila: tidak ada teks yang menyiratkan pesan terkirim jika memang tidak dikirim.

---

## Batch 2 — Notifikasi dan Penalty

- [ ] **N1 · ID notifikasi bentrok** — P0 · S
  - File: `sos_emergency/data/notification_service.dart`
  - Perbaikan: ganti `_slotId(matchId)` menjadi dua fungsi: `kickoffId(id) = id * 10 + 1`,
    `resultId(id) = id * 10 + 2`; SOS tetap `0`. Pakai ID yang sesuai di `scheduleKickoff`/`showResult`
    dan `cancelMatch` (batalkan keduanya).
  - Selesai bila: satu laga punya dua notifikasi terjadwal yang tidak saling menimpa.

- [ ] **N2 · Spam notifikasi hasil saat pertama jalan** — P0 · M
  - File: `football/providers/result_notification_provider.dart`
  - Perbaikan:
    - Saat `notified_results` kosong (pertama kali), **tandai semua laga yang sudah selesai sebagai
      "sudah dinotifikasi" tanpa menampilkannya**.
    - Notifikasi hasil hanya untuk laga tim favorit yang selesai dalam, mis., 6 jam terakhir.
    - Simpan daftar sebagai `Set<int>` dalam JSON (bukan string `'#id;'`).
  - Selesai bila: instal baru dengan data asli tidak memunculkan notifikasi hasil lama.

- [ ] **N3 · Pengingat untuk seluruh liga** — P0 · M
  - File: `football/providers/kickoff_reminder_provider.dart`, `match_center_screen.dart`
  - Perbaikan:
    - Jadwalkan hanya laga **tim favorit** (`m.involves(fav)`), maksimum 20 laga terdekat (batas iOS 64).
    - Batalkan jadwal lama saat tim favorit diganti (`cancelMatch`).
    - Tombol "Atur pengingat" memakai aturan yang sama dan menampilkan jumlah yang dijadwalkan.
    - Jadwalkan secara paralel/dibatasi, bukan 380 panggilan berurutan saat startup.
  - Selesai bila: mengganti tim favorit mengubah daftar pengingat; jumlah pending ≤ 20.

- [ ] **N4 · Notifikasi dari data contoh** — P0 · S
  - File: kedua provider notifikasi
  - Perbaikan: lewati penjadwalan jika `matchesProvider.valueOrNull?.source == DataSource.sample`.
  - Selesai bila: tanpa `FOOTBALL_API_KEY` tidak ada notifikasi laga palsu.

- [ ] **N5 · Dedupe penjadwalan hasil** — P1 · S
  - File: `result_notification_provider.dart`
  - Perbaikan: pakai signature seperti di pengingat kickoff agar `scheduleResultNotification` tidak dipanggil ulang
    untuk semua laga setiap kali data berubah.

- [ ] **P1 · Arah tendangan salah sensor** — P0 · M
  - File: `penalty_shootout/providers/penalty_provider.dart`, `data/penalty_rules.dart`
  - Perbaikan:
    - Hitung arah dari **kemiringan accelerometer** (mis. `roll = atan2(x, z)`), bukan `gyroscope.z` (itu laju putar).
    - Tampilkan penanda arah dari nilai roll yang sama.
    - Hapus ketergantungan "mode demo jika tiltZ == 0".
  - Selesai bila: memiringkan HP ke kiri/kanan menggeser penanda dan memengaruhi hasil tendangan.

- [ ] **P2 · Kekuatan tendangan hampir selalu 0** — P0 · M
  - Perbaikan:
    - Ganti tombol "Tendang" menjadi: tekan **Siap** → ayunkan HP → deteksi puncak accelerometer
      (> `minShake`) dalam jendela ±1,5 detik → tendangan otomatis dengan kekuatan = puncak tersebut.
    - Sediakan tombol cadangan "Tendang manual" (mode demo) bila sensor tidak ada.
    - Hentikan peluruhan 10% per event; simpan puncak selama jendela aktif.
  - Selesai bila: ayunan sungguhan menghasilkan power yang bervariasi dan sebagian besar tendangan tidak "terlalu lemah".

- [ ] **P3 · Rebuild 50×/detik dan farming blok** — P1 · S
  - Perbaikan:
    - Pisahkan nilai sensor ke provider/`ValueNotifier` tersendiri atau batasi ke ~15 Hz (throttle),
      supaya seluruh layar tidak dibangun ulang tiap event.
    - Cetak blok achievement hanya bila `score > 0`, **bukan** mode demo (atau tandai `demo: true` di data blok),
      dan maksimum satu blok per sesi/hari.
    - `copyWith(last: null)` tidak bisa menghapus `last` (karena `??`); beri parameter sentinel/`clearLast`.
  - Selesai bila: rantai tidak tumbuh karena main berulang; jank hilang saat sensor aktif.

---

## Batch 3 — Sinkronisasi dan Commit–Reveal

- [ ] **S1 · Hasil pull tidak diterapkan** — P0 · M
  - File: `sync/data/sync_repository.dart`, `sync/providers/sync_provider.dart`,
    `away_day_providers.dart`, `prediction_provider.dart`
  - Perbaikan:
    - Kembalikan **daftar hasil merge** (bukan hanya `.length`) dari `SyncRepository.sync`.
    - Tambahkan `replaceAll(List)` pada `AwayDayNotifier` dan `PredictionsNotifier` (simpan ke Hive),
      lalu panggil dari `SyncNotifier.run()`.
    - Ganti `_ref.watch(chainProvider)` di `run()` menjadi `_ref.read(chainProvider)`.
  - Selesai bila: hapus data lokal → sinkron → pengeluaran dan prediksi kembali.

- [ ] **S2 · Rantai tidak pernah dipulihkan** — P1 · M
  - Perbaikan: setelah pull, adopsi rantai server **hanya jika** `Blockchain.isValid(remote)`, genesis sama,
    dan lebih panjang dari rantai lokal (atau lokal hanya genesis). Selain itu pertahankan rantai lokal.
  - Selesai bila: perangkat baru memulihkan stamp dari server; rantai rusak ditolak.

- [ ] **S3 · Galat sinkronisasi tidak informatif; 401 tidak ditangani** — P1 · S
  - Perbaikan: ambil `e.response?.data['error']` dari `DioException`; pada 401 hapus sesi dan arahkan ke login.
    Simpan `lastSyncedAt` sebagai state Riverpod agar Profil langsung ter-update.

- [ ] **S4 · Salt prediksi ikut terkirim** — P1 · S (klien) + lihat B5 (server)
  - File: `sync_models.dart` (`predictionToJson`)
  - Perbaikan: sebelum kickoff kirim hanya `matchId` + `commit` + `createdAt`; kirim skor dan salt **setelah**
    blok result ditulis.

- [ ] **R1 · Verifikasi reveal harus terhadap blok rantai** — P0 · M
  - File: `prediction/providers/prediction_provider.dart`
  - Perbaikan:
    - Di `settle()`, cari blok `prediction_commit` untuk `matchId`; verifikasi dengan
      `block.data['commit']`, bukan `p.commit` dari Hive.
    - Pakai `home`/`away` dari data blok (bukan nama dari API saat ini) untuk menghitung ulang commit.
    - Tolak bila `block.data['at']` ≥ `match.kickoffUtc` atau blok tidak ditemukan.
  - Selesai bila: mengubah skor/salt/commit di Hive lalu "Buka" menghasilkan **tidak sah**.

- [ ] **R2 · Hindari kehilangan data prediksi** — P1 · S
  - Perbaikan: `Prediction.fromJson`/`PredictionStore.load` parse per-item dan lewati yang rusak
    (jangan `catch → []` untuk seluruh daftar). Await `mint` + `put` di `commit()` agar urutannya pasti.

- [ ] **R3 · Prediksi untuk laga yang tidak selesai** — P2 · S
  - Perbaikan: laga `POSTPONED`/`CANCELLED` ditandai batal (poin 0, tanpa blok result); tolak prediksi
    pada laga contoh (`DataSource.sample`).

---

## Batch 4 — Autentikasi dan data pengguna

- [ ] **U1 · Tidak ada registrasi** — P0 · M
  - File baru: `auth/presentation/register_screen.dart`; ubah `auth_repository.dart`, `auth_provider.dart`, `login_screen.dart`
  - Perbaikan: form email + password + konfirmasi; hash SHA-256 di klien; `POST /auth/register`; tangani 409
    ("Email sudah terdaftar"); tautan "Daftar" di layar login.
  - Selesai bila: akun baru bisa dibuat dari aplikasi lalu login.

- [ ] **U2 · Pesan error login mentah** — P1 · S
  - Perbaikan: petakan `DioException` → pesan Indonesia (401 "Email atau password salah", timeout "Server tidak
    terjangkau", tanpa koneksi). Terapkan juga di `lock_screen.dart`.

- [ ] **U3 · Mode mock di build rilis** — P1 · S
  - Perbaikan: di `AuthRepository.login`, tolak mode mock saat `kReleaseMode` (butuh `BACKEND_URL`).

- [ ] **U4 · Logout tidak membersihkan data / data bocor antar pengguna** — P0 · M
  - Perbaikan (pilih satu, minimal yang pertama):
    - Saat logout hapus data pengguna di Hive (pengeluaran, prediksi, rantai, foto profil, saran) **dan**
      `wallet_private_key` di secure storage, lalu `ref.invalidate` provider terkait.
    - Lebih baik: beri awalan kunci Hive/secure storage per `uid` agar tiap akun terpisah.
  - Selesai bila: login sebagai pengguna B tidak menampilkan data pengguna A.

- [ ] **U5 · Kedaluwarsa sesi mengikuti server** — P2 · S
  - Perbaikan: baca klaim `exp` dari JWT (decode base64) sebagai pengganti `sessionDuration` 7 hari tetap.

---

## Batch 5 — Hardening backend (`server/`) — semua butir (terbukti)

- [x] **B1 · Secret dev bisa memalsukan token** — P0 · S
  - File: `index.js`
  - Perbaikan: selalu `throw` bila `JWT_SECRET` kosong (hapus fallback `'dev-only-secret'`); untuk dev,
    sediakan `.env.example` dan jalankan dengan `JWT_SECRET=...`. Sesuaikan test agar menyetel secret.

- [x] **B2 · Enumerasi email lewat waktu respons** — P1 · S
  - File: `auth.js`
  - Perbaikan: buat `const DUMMY_HASH = bcrypt.hashSync('dummy', 10)` sekali saat start, bandingkan dengannya saat user
    tidak ada. Hapus hash `'$2a$10$invalid…'` dan perbaiki komentarnya.
  - Selesai bila: selisih waktu login email-ada vs email-tidak-ada < ~10 ms.

- [x] **B3 · Tanpa pembatasan percobaan; bcrypt memblokir event loop** — P1 · S
  - Perbaikan: `npm i express-rate-limit`, batasi `/auth/login` dan `/auth/register` (mis. 10 per 15 menit per IP);
    pakai `bcrypt.hash/compare` versi async + handler async (`wrap` mendukung Promise).
  - Selesai bila: percobaan ke-11 mendapat 429.

- [x] **B4 · Blok rantai bisa ditimpa dengan hash palsu** — P0 · M
  - File: `sync.js`
  - Perbaikan: `ON CONFLICT DO NOTHING` (blok yang sudah ada tidak boleh berubah); sebelum menyimpan, verifikasi tiap
    blok (SHA-256 dengan format yang sama seperti `Block.computeHash`, awalan `000`, `index` berurutan,
    `prevHash` = hash sebelumnya). Tolak dengan 400 bila tidak valid.
  - Ubah test "chain dengan indeks sama ditimpa" menjadi "blok yang sudah ada tidak berubah".

- [x] **B5 · Salt dan skor prediksi tersimpan sebelum kickoff** — P1 · M
  - File: `schema.sql`, `sync.js`
  - Perbaikan: jadikan `home_score`, `away_score`, `salt` **nullable**; terima hanya `commit` sebelum reveal;
    perbarui komentar skema agar sesuai perilaku sebenarnya. Sesuaikan test "prediksi menyimpan salt dan commit".

- [x] **B6 · Payload tidak valid → 500; tidak transaksional** — P1 · M
  - File: `sync.js`
  - Perbaikan: validasi tipe (`Number.isInteger`, `Number.isFinite`, string tidak kosong, batas panjang) dan lempar
    `HttpError(400, …)`; batasi jumlah `expenses`/`predictions` (seperti `MAX_CHAIN`); bungkus `push` dengan
    `BEGIN`/`COMMIT` dan `ROLLBACK` saat galat.
  - Selesai bila: `index: 'abc'` dan `amountGbp: 'abc'` menghasilkan 400 dan tidak ada data tersimpan sebagian.

- [x] **B7 · Perapian lain** — P2 · S
  - `ORDER BY id` pada pull expense mengurutkan berdasarkan alias; pakai `ORDER BY created_at`.
  - Hapus komentar rusak "idempoten:AUS" di `sync.js`.
  - Selaraskan `package.json` (`engines`, ketergantungan `better-sqlite3` bila memakai `node:sqlite`) dan dokumentasikan
    versi Node di README.
  - Tambah `helmet` dan dokumentasikan penggunaan HTTPS (reverse proxy) untuk produksi.

- [ ] **B8 · Proxy AI dan data football di server** — P2 · L (opsional, nilai tambah)
  - Tambahkan endpoint `POST /ai/pundit` (kunci Gemini hanya di server) dan cache `GET /football/*` di server agar
    kuota 10 req/menit tidak ditanggung tiap ponsel. Hapus `GEMINI_API_KEY` dari klien.

---

## Batch 6 — UI/UX

- [x] **UI1 · Home terlalu rata dan ada kartu ganda** — P1 · M
  - File: `dashboard/presentation/home_tab.dart`, `fan_summary.dart`, `favorite_team_card.dart`
  - Perbaikan: kelompokkan menu dengan judul bagian (Pertandingan · Seru-seruan · Alat Bantu); gabungkan
    `FanSummary` ke `FavoriteTeamCard` atau hapus duplikasi (tim, laga berikutnya); sisakan ruang bawah untuk tombol SOS.

- [x] **UI2 · Tab kehilangan state** — P1 · S
  - File: `dashboard_screen.dart`
  - Perbaikan: ganti `_pages[index]` dengan `IndexedStack` (atau `AutomaticKeepAliveClientMixin`) agar isian
    Saran dan Kesan tidak hilang saat pindah tab.

- [x] **UI3 · Layar Prediksi Skor** — P1 · M
  - File: `prediction/presentation/prediction_screen.dart`
  - Perbaikan:
    - Default tampilkan laga **tim favorit** (dengan tombol "Semua laga"), tampilkan tanggal + jam WIB di tiap pilihan,
      batasi ke ±20 laga terdekat.
    - Simpan `selectedMatchId` (int), bukan objek `FootballMatch` (hindari assertion `DropdownButton` saat data dimuat ulang).
    - "Tebakan tersimpan" tampilkan nama tim, waktu kickoff, status, dan poin setelah settle (riwayat).
    - Ganti teks "Buka salt" menjadi "Cek hasil".

- [x] **UI4 · Layar Away Day** — P1 · S–M
  - File: `away_day/presentation/away_day_screen.dart`
  - Perbaikan:
    - Normalisasi desimal: `text.replaceAll(',', '.')` sebelum `double.tryParse` (keyboard berkoma).
    - `_submit` menampilkan pesan galat (judul kosong / jumlah ≤ 0) alih-alih `return` diam-diam.
    - Saat kurs offline dan input GBP, jangan simpan `amountIdr = 0`: minta Rupiah manual atau tunda simpan.
    - Ubah judul dialog "Anggaran harian" menjadi "Anggaran total" (atau implementasikan benar-benar harian).

- [x] **UI5 · Kompas Stadion** — P2 · S
  - Perbaikan: `selectedStadiumIndex` nullable (null = ikut tim favorit), jadi berubahnya klub favorit
    ikut mengubah stadion yang dituju tanpa menimpa pilihan manual pengguna.
    Hapus provider accelerometer/gyroscope yang tidak dipakai, atau tampilkan datanya (kemiringan) dengan jelas.

- [x] **UI6 · Layar Pundit AI** — P1 · M
  - File: `pundit/presentation/pundit_screen.dart`, `pundit_provider.dart`, `pundit_repository.dart`
  - Perbaikan: nonaktifkan tombol saat loading; tampilkan chip "Data tersimpan • <waktu>"; render teks sebagai
    paragraf (minta Gemini membalas teks biasa, atau pakai `flutter_markdown`); pesan galat ramah; masukkan baris klasemen
    klub favorit + lawan berikutnya ke prompt; **jangan** memakai data contoh (tolak dengan pesan jelas); simpan cap waktu cache.

- [x] **UI7 · Lens mengenali klub** — P2 · M
  - Perbaikan: setelah OCR, cocokkan teks dengan `PlClub.isTeam`; jika cocok tampilkan tombol "Lihat jadwal <klub>".

- [x] **UI8 · Loading, kosong, aksesibilitas** — P2 · M
  - Perbaikan: skeleton sederhana untuk daftar pertandingan dan klasemen; `Semantics`/`tooltip` untuk ikon;
    uji tampilan dengan ukuran font besar dan mode gelap; pindahkan `File(photo).existsSync()` keluar dari `build`.

---

## Batch 7 — Kualitas kode dan proyek

- [x] **C1 · Penamaan konsisten** — P1 · M
  - Perbaikan: samakan nama folder, `name:` di `pubspec.yaml`, `applicationId`/namespace, label aplikasi, dan README
    (hindari "Premier League" pada nama paket/logo; pertimbangkan nama seperti `kickoffku`).
    Ganti `com.example.*` dengan ID unik; ikuti `flutter pub get` + `flutter clean` setelah rename.

- [x] **C2 · Penyimpanan** — P1 · M
  - Perbaikan: tambahkan `schema_version` di Hive + fungsi migrasi; parse per-item toleran di semua `fromJson`
    (`AwayDayExpense`, `Prediction`, `Block`); kunci data per pengguna (lihat U4); cache `ratesProvider` di Hive dengan
    cap waktu agar konversi tetap bisa dipakai offline.

- [x] **C3 · Kode mati dan janggal** — P2 · S
  - Hapus `pendingResultNotificationsProvider` (tak terpakai) dan `rates?['GBP'] ?? rates?['GBP']`;
    hapus/ganti `Speed Tapper` bila Penalty menggantikannya; hapus `sessionHash` redundan atau ubah fungsinya;
    rapikan indentasi `_syncSubtitle` (`dart format .`); hapus `TODO` setelah F3.

- [x] **C4 · Higiene repositori** — P2 · S
  - Perbaikan: tambahkan `.gitattributes` (`* text=auto eol=lf`) lalu normalisasi `git add --renormalize .`;
    pastikan `.idea/`, `android/.gradle/`, `android/local.properties`, `server/node_modules/`, `server/data/` tidak ikut
    zip/commit; naikkan `flutter_lints` dan aktifkan aturan tambahan
    (`avoid_print`, `use_build_context_synchronously`, `unawaited_futures`, `prefer_const_constructors`).

- [x] **C5 · Konfigurasi platform** — P1 · S–M
  - Android: hilangkan `USE_EXACT_ALARM` (cukup `SCHEDULE_EXACT_ALARM` + minta izin lewat
    `requestExactAlarmsPermission()`), siapkan keystore rilis (jangan `signingConfig = debug`).
  - iOS: di `AppDelegate.swift` set `UNUserNotificationCenter.current().delegate` agar notifikasi tampil saat aplikasi
    terbuka; uji izin lokasi/kamera/notifikasi.

- [x] **C6 · Konfigurasi dan dokumentasi** — P2 · S
  - Perbarui README dan `GUIDELINE_LANJUTAN.md`: daftar `--dart-define` (`GEMINI_API_KEY`, `GEMINI_MODEL`,
    `FOOTBALL_API_KEY`, `BACKEND_URL`), cara menjalankan server (`JWT_SECRET`, versi Node), dan batasan yang diketahui.

---

## Batch 8 — Pengujian

- [x] **T1 · Test logika yang belum ada** — P1 · M
  - `test/blockchain_test.dart`: rantai valid; data diubah/blok dihapus/hash dipalsukan terdeteksi.
  - `test/time_utils_test.dart`: batas DST London/AS/Sydney (mis. 29 Mar 2026 01:00 UTC, 25 Okt 2026 01:00 UTC).
  - `test/price_parser_test.dart`: `1,200` (JPY), `1.234,56`, `12.50`, nomor telepon diabaikan.
  - `test/football_models_test.dart`: parse respons nyata (simpan satu cuplikan JSON football-data.org sebagai fixture),
    termasuk field kosong dan alias klub (`PlClub.isTeam` untuk 20 klub + 3 klub degradasi tidak cocok).
  - `test/notification_ids_test.dart`: `kickoffId` ≠ `resultId`; tidak ada tabrakan untuk rentang ID laga.

- [x] **T2 · Test perilaku (bukan hanya fungsi murni)** — P1 · L
  - Commit–reveal: reveal **ditolak** bila commit di Hive diubah tetapi blok rantai tidak (R1).
  - Sinkronisasi: hasil merge benar-benar diterapkan ke notifier (S1).
  - Notifikasi: daftar yang dijadwalkan hanya laga tim favorit dan ≤ 20 (N3); laga selesai lama tidak dinotifikasi (N2).
  - Penalty: pemetaan sensor → arah/kekuatan dengan nilai accelerometer sintetis (P1–P2).

- [x] **T3 · Test server yang mengunci perilaku benar** — P1 · M
  - Ganti test yang mengunci perilaku keliru (blok ditimpa, salt tersimpan) dengan yang baru dari B4/B5.
  - Tambah: login tanpa `JWT_SECRET` gagal start (B1); percobaan ke-11 → 429 (B3); payload tidak valid → 400
    dan tidak ada tulis sebagian (B6); blok dengan hash palsu → 400 (B4).

- [ ] **T4 · Uji manual di perangkat fisik** — P0 · M
  - Stamp (GPS dan demo), kompas, penalty dengan sensor asli, pengingat kickoff (jadwalkan laga dalam 2 menit),
    biometrik, sinkronisasi dua perangkat/akun, SOS, mode offline (matikan internet), tema gelap.
  - Lembar uji: **LEMBAR_UJI_T4.md** (19 baris, kolom hasil aktual dan bukti).
  - Pending: `flutter run --dart-define=KICKOFF_REMINDER_MINUTES=2` supaya pengingat bisa
    dibuktikan tanpa menunggu 30 menit, plus `usesCleartextTraffic` di manifest debug untuk sinkronisasi via LAN.

---

## Urutan kerja ringkas

| Urutan | Batch | Tujuan |
|---|---|---|
| 1 | Batch 1 (F1–F3) | Fitur utama bisa didemokan |
| 2 | Batch 2 (N1–N5, P1–P3) | Notifikasi benar dan game memakai sensor sungguhan |
| 3 | Batch 3 (S1–S4, R1–R3) | Database online dan blockchain bermakna |
| 4 | Batch 4 (U1–U5) | Akun dapat dipakai dan tidak bocor antar pengguna |
| 5 | Batch 5 (B1–B8) | Backend aman |
| 6 | Batch 6–7 (UI, kode) | Polesan dan kerapian |
| 7 | Batch 8 (T1–T4) | Bukti pengujian untuk laporan |

**Definisi selesai proyek:** `flutter analyze` bersih, `flutter test` dan `npm test` hijau, seluruh butir **P0** tercentang,
dan checklist uji manual (T4) terisi hasilnya untuk lembar evaluasi laporan.

**Status saat ini (2026-10-05):** Batch 1–7 selesai dan ter-commit; T1–T3 tercentang. T4 sudah punya lembar uji
(`LEMBAR_UJI_T4.md`) tetapi **belum diisi** — masih butuh satu perangkat fisik, jadi T4 tetap terbuka.
