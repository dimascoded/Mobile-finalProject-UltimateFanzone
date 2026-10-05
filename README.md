# Smart Football Fan (Liga Inggris)

Panduan lengkap ada di **GUIDELINE_LANJUTAN.md**.

| Item | Nilai |
|---|---|
| Nama paket Dart | `smart_football_fan` |
| Label aplikasi | Smart Football Fan |
| `applicationId` / namespace Android | `com.smartfootballfan` |
| Bundle ID iOS | `com.smartfootballfan` |

> Folder repositori masih bernama `smart_global_traveler` (nama lama tidak diubah
> supaya riwayat Git tetap terhubung). Nama paket dan ID di dalam proyek sudah
> memakai `smart_football_fan` / `com.smartfootballfan`.

## Setup
```bash
cd smart_global_traveler
# Proyek sudah lengkap; perintah di bawah hanya bila perlu meregenerasi
# platform. JANGAN timpa lib/main.dart & pubspec.yaml.
flutter pub get
flutter analyze
flutter run \
  --dart-define=GEMINI_API_KEY=ISI_KEY_ANDA \
  --dart-define=FOOTBALL_API_KEY=KEY_FOOTBALL_DATA
# opsional: --dart-define=BACKEND_URL=https://backend-anda.com  (kosong = login mock)
# opsional: --dart-define=KICKOFF_REMINDER_MINUTES=2  (hanya uji manual, produksi 30)
```

## Uji manual di perangkat

Lembar uji lengkap (19 baris, kolom hasil dan bukti) ada di
**LEMBAR_UJI_T4.md**, termasuk cara menjalankan backend lokal dan mengambil
alamat IP PC untuk sinkronisasi. Ringkasnya:

```bash
# terminal 1 - server sinkronisasi
cd server && npm install && cp .env.example .env
# isi JWT_SECRET di .env, lalu:
node --env-file=.env index.js

# terminal 2 - aplikasi (HP dan PC harus di Wi-Fi yang sama)
ipconfig                       # ambil IPv4 Address, mis. 192.168.1.5
flutter run \
  --dart-define=BACKEND_URL=http://192.168.1.5:3000 \
  --dart-define=KICKOFF_REMINDER_MINUTES=2
```

- `KICKOFF_REMINDER_MINUTES=2` hanya untuk uji, supaya pengingat kickoff bisa
  dibuktikan dalam 2-5 menit tanpa menunggu 30 menit. Nilai produksi tetap 30.
- HTTP ke IP lokal hanya diizinkan pada **build debug**
  (`android/app/src/debug/AndroidManifest.xml`). Build rilis tetap menolak trafik
  cleartext. Di iOS, HTTP diblokir ATS, jadi pakai tunnel HTTPS untuk pengujian.

## Izin Android — android/app/src/main/AndroidManifest.xml (di dalam <manifest>)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.CAMERA"/>
```
- Ganti `MainActivity` menjadi `FlutterFragmentActivity` (syarat local_auth).
- `android/app/build.gradle`: `minSdkVersion 23` (secure storage + ML Kit).

## Izin iOS — ios/Runner/Info.plist
`NSLocationWhenInUseUsageDescription`, `NSFaceIDUsageDescription`,
`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`.
`ios/Podfile`: `platform :ios, '15.5'` (syarat ML Kit).

## Data pertandingan (football-data.org)
1. Daftar gratis di https://www.football-data.org/client/register lalu ambil API key.
2. Uji key Anda (satu perintah):
```bash
curl -H "X-Auth-Token: KEY_ANDA" https://api.football-data.org/v4/competitions/PL/matches
```
3. Jalankan app dengan `--dart-define=FOOTBALL_API_KEY=KEY_ANDA`.
- Tanpa key, app memakai **DATA CONTOH** (ada banner merah) — bukan jadwal resmi.
- Tier gratis: 10 request/menit, skor tertunda. Hasil di-cache 15 menit di Hive; jika gagal, data terakhir dipakai.
- Jangan commit API key ke repositori publik.

## Server sinkronisasi (opsional)

Backend sinkronisasi hanya dipakai bila aplikasi dijalankan dengan
`--dart-define=BACKEND_URL=https://...`. Tanpa `BACKEND_URL`, login dan
sinkronisasi memakai mode lokal (mock).

```bash
cd server
npm install
cp .env.example .env        # isi JWT_SECRET (wajib, B1)
node --env-file=.env index.js
# endpoint: http://localhost:3000  (cek http://localhost:3000/health)
```

- **Wajib Node.js 22.5 atau lebih baru** (`node -v`): driver utama memakai
  `node:sqlite` bawaan Node. `better-sqlite3` hanya cadangan bila modul itu tidak
  tersedia.
- `JWT_SECRET` wajib diisi. Server berhenti saat start kalau kosong, jadi tidak
  mungkin berjalan dengan kunci yang ditebak.
- `helmet` dipasang untuk header keamanan; `express-rate-limit` membatasi
  `/auth/login` dan `/auth/register` (default 10 percobaan / 15 menit / IP).
- Di produksi, taruh server di belakang reverse proxy yang mengakhiri TLS dan
  set `TRUST_PROXY_HOPS` sesuai jumlah proxy di depan server.
- Batasan yang diketahui: blok rantai yang sudah tersimpan tidak bisa diedit
  (ditolak dengan 400), salt dan skor prediksi hanya diterima bersama-sama
  sebagai bentuk ter-reveal, dan `POST /sync` dibatasi 5 MB per request.

## Build rilis Android (C5)

Buat keystore sekali, lalu isi `android/key.properties` (file itu di-ignore Git):

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/path/ke/upload-keystore.jks
```

Tanpa file itu, `flutter build apk --release` tetap berjalan memakai debug key
(berguna untuk demo lokal) tetapi APK-nya tidak boleh diunggah ke Play Store.
