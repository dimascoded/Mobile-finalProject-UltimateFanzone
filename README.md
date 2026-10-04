# Smart Football Fan (Liga Inggris)

Panduan lengkap ada di **GUIDELINE_LANJUTAN.md**.

## Setup
```bash
cd smart_global_traveler
flutter create . --org com.example --project-name premiere_league_fan_assistant
# JANGAN timpa lib/main.dart & pubspec.yaml. Hapus test/widget_test.dart bawaan.
flutter pub get
flutter analyze
flutter run \
  --dart-define=GEMINI_API_KEY=ISI_KEY_ANDA \
  --dart-define=FOOTBALL_API_KEY=KEY_FOOTBALL_DATA
# opsional: --dart-define=BACKEND_URL=https://backend-anda.com  (kosong = login mock)
```

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
