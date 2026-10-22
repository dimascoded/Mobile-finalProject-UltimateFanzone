# Peta Fitur — Ultimate Fanzone

> Dokumen ini menjelaskan **cara kerja tiap fitur dari ujung ke ujung**: alur data
> (`presentation` -> `providers` -> `data` -> penyimpanan/jaringan), logika yang
> bercabang, serta peran tiap berkas. Pasangan naratif dari komentar `///` inline
> di kode. Bahasa Indonesia, tanpa emoji.
>
> Arsitektur: **Feature-Driven Clean Architecture + Riverpod**. Tiap fitur punya
> `data/` (I/O dan model), `providers/` (state & efek samping), `presentation/`
> (widget). Aturan wajib ada di `GUIDELINE_LANJUTAN.md` bagian 3.

---

## 0. Alur Startup (titik masuk)

```text
main()
  ├─ HiveService.init()                  # buka box 'app_cache'
  ├─ OfflineSyncDatabase.initialize()    # buka SQLite smart_football_fan.db
  ├─ OfflineSyncDatabase.importHiveData()# migrasi data lama Hive -> SQLite
  ├─ (validasi) SUPABASE_URL + ANON_KEY harus lengkap bersama
  ├─ Supabase.initialize()               # sesi disimpan di secure storage
  ├─ NotificationService.init()          # kanal + izin notifikasi lokal
  └─ runApp(ProviderScope(MyApp))

MyApp.build
  ├─ watch(sessionProvider)              # true -> LockScreen, false -> LoginScreen
  ├─ watch(themeModeProvider)            # tema terang/gelap
  ├─ watch(kickoffReminderSyncProvider)  # jadwalkan pengingat kickoff
  ├─ watch(resultNotifierSyncProvider)   # notifikasi hasil akhir
  └─ watch(pruneNotifiedProvider)        # bersihkan catatan notifikasi lama
```

`sessionProvider` adalah gerbang: sesi Supabase valid -> `LockScreen` (biometrik
via `local_auth`), tidak ada/kedaluwarsa -> `LoginScreen`.

---

## 1. Auth

**Tujuan:** login/registrasi akun (Supabase atau mode lokal), sesi tahan lama,
kunci biometrik, logout bersih per pengguna.

### Alur data

```text
LoginScreen / RegisterScreen
  └─ authProvider (StateNotifier)
        ├─ AuthRepository.login/register
        │     ├─ Supabase terkonfigurasi -> Supabase auth, sesi di secure storage
        │     └─ tidak terkonfigurasi   -> mode lokal (terima email+password tidak kosong)
        └─ sukses -> sessionProvider = true -> LockScreen

LockScreen (biometrik)
  └─ auto_lock_observer memantau siklus hidup aplikasi -> kunci lagi saat kembali

Logout flow
  └─ logout_flow + user_data_cleanup -> invalidate provider per pengguna
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/auth_repository.dart` | Autentikasi, kunci Firebase/Hive per pengguna, migrasi legacy, pesan error Indonesia |
| `data/identity_store.dart` | Abstraksi penyimpanan identitas (nama, foto, tim favorit) |
| `domain/auto_lock_policy.dart` | Aturan kapan aplikasi harus dikunci ulang |
| `providers/auth_provider.dart` | State sesi login/register/logout |
| `providers/user_data_cleanup.dart` | Kontrak 3 fungsi invalidate + `last_user_id` agar data pengguna lama tidak bocor |
| `presentation/*` | Layar login, register, kunci, observer, alur logout |

### Logika bercabang

- **Sesi valid vs tidak** ditentukan `sessionProvider` (dari Supabase session).
- **Auto-lock**: `auto_lock_observer` mengunci ketika aplikasi masuk background
  melewati ambang `auto_lock_policy`.
- **Per-pengguna**: key preferensi (nama, foto, tim favorit) di-scope ke akun;
  saat logout, `user_data_cleanup` meng-invalidate provider dan membaca
  `last_user_id` untuk membersihkan sisa data pengguna sebelumnya.

---

## 2. Dashboard

**Tujuan:** kerangka bottom-nav (Home, Fitur, Profil) + hero, statistik, kartu
tim favorit, menu fitur, dan tombol SOS mengambang.

### Alur data

```text
DashboardScreen
  ├─ HomeTab        -> home_hero, home_stats, upcoming_matches, cards_teaser, quick_actions
  ├─ FeatureMenuTab -> menu_groups (registry MenuItem) -> fitur lain
  └─ ProfileTab     -> profile_header, profile_sections, feedback_screen

Semua angka berasal dari dashboardProvider (agregat) dan provider fitur terkait.
SosHoldButton (FAB merah) selalu tampil; tahan 3 detik -> SosNotifier.trigger.
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `presentation/dashboard_screen.dart` | Scaffold + bottom navigation |
| `presentation/home_tab.dart` | Isi tab Home |
| `presentation/feature_menu_tab.dart` / `feature_cards.dart` | Daftar fitur |
| `presentation/menu_groups.dart` | Registry `MenuItem(label, description, icon, page, badge)` |
| `presentation/profile_tab.dart` | Isi tab Profil |
| `presentation/feedback_screen.dart` | Kesan & saran (key Hive `pam_feedback`) |
| `presentation/widgets/home_hero.dart` | Hero "malam laga" |
| `presentation/widgets/home_stats.dart` | Satu `Row` berisi 3 `Expanded(StatTile)` |
| `presentation/widgets/upcoming_matches.dart` | Laga berikutnya tim favorit |
| `presentation/widgets/profile_header.dart` | Header profil (tinggi `230 * textScaler`) |
| `providers/dashboard_provider.dart` | Data agregat untuk header/statistik |

### Logika bercabang

- Menu fitur dibentuk dari `menu_groups`; `badge` pada `MenuItem` menandai fitur
  yang punya notifikasi/keadaan khusus.
- SOS selalu terjangkau lewat FAB; padding bawah daftar Home 96dp agar tidak
  tertutup.

---

## 3. Football (Match Center)

**Tujuan:** jadwal, klasemen, top skor, pemilihan tim favorit, pengingat kickoff,
dan notifikasi hasil. Poros aplikasi.

### Alur data

```text
footballProvider / matchesProvider / standingsProvider / scorersProvider
  └─ FootballRepository
        ├─ ada FOOTBALL_API_KEY -> GET api.football-data.org/v4
        │     ├─ cache Hive: fd_matches / fd_standings / fd_scorers (+ '_at')
        │     └─ TTL 15 menit (jendela live 3 menit)
        └─ tanpa key -> sample_data + data_source_banner (banner merah)

favoriteTeam -> filter kartu tim favorit + pengingat
kickoff_reminder_provider -> NotificationService.zonedSchedule (izin exact alarm)
result_notification_provider -> notifikasi hasil akhir (batas usia 6 jam)
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/football_repository.dart` | Klien API + cache Hive (`fd_*`) + TTL |
| `data/models.dart` | DTO football-data.org v4 (`tryParse`, `phaseAt`, `PlClub.isTeam`) |
| `data/reminder_leads.dart` | Normalisasi lead waktu pengingat |
| `data/sample_data.dart` | Data contoh deterministik (tanpa API key) |
| `providers/football_providers.dart` | Laga/klasemen/top skor/klub favorit |
| `providers/kickoff_reminder_provider.dart` | Jadwal notifikasi kickoff |
| `providers/result_notification_provider.dart` | Notifikasi hasil akhir |
| `presentation/match_center_screen.dart` | Jadwal 4 zona waktu, filter, cari tim |
| `presentation/team_picker_screen.dart` | Pilih tim favorit |
| `presentation/reminder_settings_screen.dart` | Atur lead pengingat |
| `presentation/kickoff_times.dart` | Konversi tampilan jam kickoff |
| `presentation/club_crest.dart` / `data_source_banner.dart` | Lencana klub, banner sumber data |

### Logika bercabang

- **Ada/tidak API key**: tanpa key, semua data dari `sample_data` dan pengingat
  sengaja dimatikan; banner merah memperingatkan pengguna.
- **TTL cache**: respons dianggap segar 15 menit, tetapi laga berstatus live
  dianggap segar 3 menit saja.
- **Pengingat**: hanya untuk laga tim favorit; ID notifikasi kickoff dibedakan
  dari ID notifikasi hasil.

---

## 4. Away Day

**Tujuan:** kalkulator biaya menonton langsung (GBP -> Rp), kategori pengeluaran,
anggaran total, dan konversi waktu kota tujuan.

### Alur data

```text
awayDayProviders (expenses / budget / totals)
  └─ AwayDayRepository (koleksi sync 'away_day_expenses')
        ├─ Hive box 'app_cache' (cermin offline)
        └─ OfflineSyncDatabase (SQLite) untuk sinkronisasi
currency_convert: kurs IDR dibagi (base IDR) -> GBP/IDR dsb.
city_time: waktu kota tujuan (rule none/eu/us/au)
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/away_day_repository.dart` | CRUD pengeluaran (koleksi `away_day_expenses`) |
| `data/currency_convert.dart` | Konversi mata uang; **kurs dibagi, bukan dikali** |
| `data/city_time.dart` | Jam kota tujuan |
| `providers/away_day_providers.dart` | State pengeluaran, anggaran, total |
| `presentation/away_day_screen.dart` | Layar utama (input, tabel, total) |

### Logika bercabang

- **Anggaran**: bila total pengeluaran melampaui anggaran, tampilan menandai
  kelebihan; anggaran per pengguna disimpan lewat `auth_repository`.
- **Kategori**: `AwayDayCategory` (enum), default `lainnya` saat parsing gagal.

---

## 5. Sync

**Tujuan:** sinkronisasi dua arah offline-first ke backend (Supabase atau Node),
dengan pemulihan data saat ganti perangkat.

### Alur data

```text
syncProvider (StateNotifier<AsyncValue<DateTime?>>)
  └─ SyncRepository
        ├─ pilih backend: Supabase -> Node (/sync) -> lokal/mock
        ├─ push: {expenses, chain, predictions, feedback}
        ├─ pull: data milik user -> merge
        └─ 401 -> logout; respons rusak -> tolak

merge (sync_models.dart):
  mergeExpenses      -> id sama tidak digandakan; versi LOKAL menang
  mergePredictions   -> satu per matchId; lokal menang; prediksi terhapus tetap terhapus
  chainToJson        -> rantai TIDAK digabung (Butuh mining ulang); lokal sumber kebenaran
  partitionDeletions -> 'score_predictions' dihapus langsung; 'away_day_expenses' via tombstone
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/sync_repository.dart` | Pemilihan backend + push/pull |
| `data/sync_models.dart` | Bentuk payload, merge, partisi penghapusan |
| `data/chain_reconcile.dart` | Rekonsiliasi blok rantai dengan server |
| `providers/sync_provider.dart` | Aksi sinkron manual, validasi sebelum menimpa |

### Logika bercabang

- **Urutan backend**: Supabase -> Node -> lokal (mock). Ini yang membuat app tetap
  jalan tanpa server.
- **Konflik**: untuk pengeluaran & prediksi, data lokal selalu menang (server =
  cadangan). Prediksi yang dihapus tidak "bangkit" kembali.
- **Rantai blok**: tidak pernah ditimpa dari server tanpa validasi
  `Blockchain.isValid`; karena PoW, rantai server tidak bisa disambung sembarangan.

---

## 6. Gamification

**Tujuan:** Fan Passport berbasis blockchain lokal: stamp stadion/nobar,
pencapaian mini game, kartu klub, dan dompet Web3 sebagai `owner` blok.

### Alur data

```text
gamificationProviders
  ├─ chainRepositoryProvider -> ChainRepository ('passport_chain')
  │     load(): toleran (C2) - blok rusak dilewati, fallback genesis
  │     save(): lewat OfflineSyncDatabase.persist
  ├─ walletRepositoryProvider -> getOrCreateAddress (secure: 'wallet_private_key')
  └─ cardCollectionProvider -> koleksi kartu klub

Blockchain (data/blockchain.dart):
  Block: index | timestamp | type | data | owner | prevHash | nonce -> SHA-256
  PoW difficulty 3 (hash mulai '000'); Blockchain.isValid cek hash, PoW, index, prevHash
  Genesis menjadi blok dasar bila penyimpanan kosong/rusak
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/blockchain.dart` | Block, genesis, PoW, `isValid`, `canonicalDataJson` |
| `data/chain_repository.dart` | Baca/tulis rantai (toleran parse) |
| `data/wallet_repository.dart` | Alamat dompet Web3 (secure storage) |
| `data/reflex_rules.dart` | Aturan mini game Refleks Kiper (murni) |
| `domain/club_card.dart` | Model kartu klub |
| `providers/gamification_providers.dart` | Rantai, stamp, pencapaian |
| `providers/card_collection_provider.dart` | Koleksi kartu |
| `presentation/passport_screen.dart` | Tampilan paspor + validasi rantai |
| `presentation/game_screen.dart` | Mini game |
| `presentation/card_collection_screen.dart` | Koleksi kartu |
| `presentation/widgets/card_reveal_overlay.dart` | Animasi buka kartu |

### Logika bercabang

- **Stamp**: wajib <= 500 m dari stadion; **mode demo** melewati GPS dan menandai
  blok `gps_verified: false` (jujur di laporan).
- **Parse toleran**: blok rusak dilewati satu per satu; jika semua hilang, kembalikan
  genesis agar rantai tetap valid.

---

## 7. Prediction

**Tujuan:** prediksi skor commit-reveal berbasis poin (tanpa taruhan).

### Alur data

```text
predictionProvider
  ├─ Prediction.computeCommit = sha256('matchId|home|away|salt')
  ├─ SEBELUM kickoff: blok 'prediction_commit' (tanpa salt & skor)
  ├─ blok di-mine (PoW)
  └─ SESUDAH FINISHED: blok 'prediction_result' membuka salt + skor
        verify() -> sha256 dengan salt terbuka harus == commit
        scorePoints(): pas=3, meleset 1=2, meleset 2=1, >2=0, +1 arah benar
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/prediction_repository.dart` | `Prediction`, commit/result data, `verify`, `scorePoints`, rank |
| `data/prediction_rank.dart` | Peringkat & progres ke peringkat berikut |
| `data/reveal_verifier.dart` | Verifikasi reveal |
| `providers/prediction_provider.dart` | Buat/lihat prediksi, hitung poin |
| `presentation/prediction_screen.dart` | Layar prediksi & riwayat |

### Logika bercabang

- **Commit-only vs revealed**: sebelum laga hanya commit; sesudah laga salt dibuka.
- **Integritas**: reveal ditolak bila commit tidak cocok -> poin tidak diberikan.

---

## 8. Lens

**Tujuan:** OCR tiket/poster/menu (on-device ML Kit) -> cocokkan klub, parse harga
-> konversi ke Rupiah.

### Alur data

```text
lensProvider (StateNotifier<AsyncValue<LensResult?>>)
  └─ LensRepository.recognize()
        ├─ ML Kit OCR -> teks
        ├─ receipt_parser: cocokkan klub via PlClub.isTeam, ekstrak item
        │     (re-export detectClubs)
        ├─ price_parser: 1,234.56 vs 1.234,56; JPY/KRW tanpa pecahan
        └─ expense_mapper -> draft pengeluaran (bisa dikirim ke Away Day)
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/lens_repository.dart` | Jalankan OCR |
| `data/receipt_parser.dart` | Parse teks, `detectClubs`, cocokkan klub |
| `data/price_parser.dart` | Parse nominal mata uang (locale-aware) |
| `data/expense_mapper.dart` | Petakan hasil -> draft pengeluaran |
| `providers/lens_provider.dart` | `LensResult`, `scan`, `clear` |
| `presentation/lens_screen.dart` | Kamera + hasil |

### Logika bercabang

- **Mata uang tanpa pecahan** (JPY/KRW) tidak memakai desimal.
- **Bahasa non-Latin** (Jepang/Korea/Thai/Arab) tidak diterjemahkan; hanya angka
  yang diandalkan.

---

## 9. Stadium Pointer (Kompas + Rute)

**Tujuan:** tunjuk arah ke stadion (GPS + magnetometer + accel + gyro) dan rute OSRM.

### Alur data

```text
ar_providers (autoDispose)
  ├─ sensor: magnetometer (heading), accelerometer, gyroscope, GPS
  ├─ bearing = arah ke stadion; panah = bearing - heading
  └─ routeRepository.parseOsrmRoute -> router.project-osrm.org/v1/driving (jarak, durasi)

PermissionGate meminta izin lokasi sekali (+ penjelasan).
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/route_repository.dart` | OSRM + `parseOsrmRoute` |
| `providers/ar_providers.dart` | Stream sensor (autoDispose) + jarak/arah |
| `presentation/stadium_pointer_screen.dart` | Layar kompas/rute |

### Logika bercabang

- **Kalibrasi**: heading bisa meleset di dekat logam; tampilkan peringatan
  kalibrasi (gerakkan angka 8) bila perlu.
- **Emulator**: tidak punya magnetometer -> uji di perangkat fisik.

---

## 10. Penalty Shootout

**Tujuan:** mini game adu penalti memakai gyroscope & accelerometer (arah =
kemiringan, kekuatan = ayunan).

### Alur data

```text
penaltyProvider (autoDispose, sensor-driven)
  ├─ penalty_rules (murni):
  │     bandFromShake / rollFromAccel / pitchFromAccel / shakeFromAccel
  │     zoneFromAim -> KickZone (2 baris x 3 kolom)
  │     chooseKeeperZone(rnd, history): 40% meniru zona tersering, sisanya acak
  │     resolveKick(zone, band, keeperZone) -> KickResult(outcome, reason)
  │     sessionScore: 100/gol, +50 sudut atas sweet, +50 sudden death
  │     inSuddenDeath: 5 tendangan pertama semua gol
  └─ demoShot(rnd): tendangan tiruan tanpa sensor
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/penalty_rules.dart` | Semua aturan murni + `KickResult` |
| `providers/penalty_provider.dart` | State permainan dari sensor |
| `presentation/penalty_screen.dart` | Gim penalti |

### Logika bercabang

- **Kekuatan**: `tooHard` selalu melambung; `sweet` ke sudut atas menembus tebakan
  kiper.
- **Kiper**: zona sama -> ditepis; bersebelahan + ayunan lemah -> ditepis.
- **Sudden death** setelah 5 tendangan pertama semuanya gol.

---

## 11. Pundit AI

**Tujuan:** analisis/obrolan sepak bola via Gemini, diberi klasemen & hasil
terakhir sebagai bahan; cache saat offline.

### Alur data

```text
punditProvider
  └─ PunditRepository (Gemini generateContent)
        ├─ system instruction + pemangkasan giliran (pundit_chat)
        ├─ bahan: klasemen + 5 hasil terakhir (dari FootballRepository)
        ├─ tanpa GEMINI_API_KEY -> pesan jelas (bukan data contoh)
        └─ cache Hive: pundit_* (badge cache / model)
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/pundit_repository.dart` | Panggilan Gemini + cache |
| `data/pundit_chat.dart` | System instruction + trim riwayat |
| `providers/pundit_provider.dart` | State obrolan/loading/error |
| `presentation/pundit_screen.dart` | Layar obrolan |

### Logika bercabang

- **Tanpa key**: tampilkan pesan konfigurasi, bukan jawaban palsu.
- **Offline**: pakai cache terakhir dengan badge "cache".

---

## 12. SOS Emergency

**Tujuan:** panggilan darurat cepat: tahan tombol 3 detik atau goyang HP, nomor
darurat UK (999/112), notifikasi lokal berisi koordinat.

### Alur data

```text
sosProvider (SosNotifier)
  └─ trigger(): kirim notifikasi lokal (slot ID 0) + tampilkan aksi darurat
sos_hold_button: tahan 3 detik (lepas sebelum -> batal)
shakeProvider (autoDispose): accelerometer > 25 m/s², 2 hentakan < 1 detik,
  cooldown 5 detik -> dialog konfirmasi (TIDAK kirim otomatis)

NotificationService: slot ID = matchId*10 + {1,2,3,4}; 0 khusus SOS
```

### Peran berkas

| Berkas | Peran |
|---|---|
| `data/notification_service.dart` | Inisialisasi notifikasi + skema ID, nomor darurat |
| `providers/sos_provider.dart` | `SosNotifier`, `trigger` |
| `providers/shake_provider.dart` | Deteksi goyang (autoDispose) |
| `presentation/sos_screen.dart` | Layar SOS + nomor darurat |
| `presentation/sos_hold_button.dart` | Tombol tahan 3 detik |
| `presentation/sos_actions.dart` | Aksi panggilan/notifikasi |

### Logika bercabang

- **Goyang**: hanya memunculkan dialog konfirmasi, tidak mengirim otomatis.
- **Batasan jujur**: tidak ada backend pengirim SOS; hanya notifikasi lokal +
  petunjuk nomor darurat.

---

## Lampiran A — Kunci penyimpanan

### Hive (box `app_cache`, semua nilai = string JSON)

| Key | Isi |
|---|---|
| `favorite_team` | Key klub favorit (mis. `arsenal`) |
| `fd_matches` / `fd_standings` / `fd_scorers` (+`_at`) | Cache football-data.org |
| `passport_chain` | Daftar blok (blockchain) |
| `pundit_*` | Cache Pundit AI (badge/model) |
| `pam_feedback` | `{kesan, saran}` |
| `theme_mode` | `system` / `light` / `dark` |
| `permission_rationale` | Izin yang sudah dijelaskan |
| `profile_photo_path` | Path foto profil |

Kunci per-pengguna lain (nama tampilan, anggaran away day, foto) di-scope ke akun
oleh `AuthRepository` (`last_user_id` menandai pemilik terakhir).

### Secure storage (`flutter_secure_storage`)

| Key | Isi |
|---|---|
| `supabase_auth_session` | Sesi Supabase (JSON) |
| `wallet_private_key` | Kunci privat dompet Web3 (owner blok) |

### SQLite (`smart_football_fan.db`)

Tabel `sync_documents` (dokumen sinkronisasi) dan `sync_deletions` (tombstone).
Koleksi sinkron: `away_day_expenses`, `passport_chain`, `score_predictions`.

---

## Lampiran B — Endpoint eksternal

| Layanan | URL dasar | Dipakai oleh |
|---|---|---|
| football-data.org v4 | `https://api.football-data.org/v4` | Football |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | Pundit |
| ExchangeRate API v4 | `https://api.exchangerate-api.com/v4/latest/IDR` | Away Day / Lens |
| OSRM | `https://router.project-osrm.org/route/v1/driving` | Stadium Pointer |
| Supabase | dari `SUPABASE_URL` | Auth / Sync |

---

## Lampiran C — Alur lintas fitur

```text
Football ──(klasemen + hasil)──> Pundit
Football ──(tim favorit)───────> Dashboard, Kickoff Reminder, Result Notification
Lens ─────(draft pengeluaran)──> Away Day
Prediction ──(blok commit/result)──> Gamification (rantai)
Gamification + Away Day + Prediction ──(payload)──> Sync
Dashboard ──(FAB SOS)──> SOS Emergency
```
