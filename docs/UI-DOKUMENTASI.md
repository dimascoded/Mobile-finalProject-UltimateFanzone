# Dokumentasi UI — Ultimate Fanzone

> **Dokumen ini adalah catatan BASELINE tampilan aplikasi, bukan spesifikasi perubahan.**
> Semua isi di sini menggambarkan UI **seperti adanya pada kode saat ini** (Flutter 3.x, Material 3).
> Tujuannya: menjadi acuan tunggal untuk (a) memahami kenapa sebuah layar terlihat seperti sekarang,
> dan (b) membandingkan "sebelum / sesudah" ketika suatu perubahan UI dilakukan.
>
> Tidak ada kode yang diubah untuk membuat dokumen ini. Setiap angka di bawah bisa dilacak
> ke file + nomor baris yang disebut.

| | |
|---|---|
| Aplikasi | `ultimate_fanzone` v1.1.0+2 (`pubspec.yaml:1,4`) |
| Framework | Flutter · Dart SDK `>=3.2.0 <4.0.0` |
| Material | `useMaterial3: true` (`lib/core/theme/app_theme.dart:90`) |
| State | `flutter_riverpod ^2.4.9` |
| Navigasi | `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` (tanpa router terpusat) |
| Font | `BarlowCondensed` (display) · `Inter` (body) |
| Mode tema | Terang + gelap, pilihan pengguna disimpan di Hive (`theme_mode`) |
| Jumlah halaman | 18 file `*_screen.dart` → **21 halaman** yang bisa dicapai pengguna |

---

## 0. Cara membaca dokumen ini

### 0.1 Konvensi penulisan

| Penanda | Arti |
|---|---|
| `file.dart:12` | Lokasi sumber nilai tersebut di kode |
| `scheme.primary` | `Theme.of(context).colorScheme.primary` |
| `fz.accent` | `context.fz.accent` → `ThemeExtension<FanzoneColors>` |
| `AppSpacing.lg` | Token jarak = `16.0` |
| `AppRadius.lg` | Token radius = `20.0` |
| `Colors.white` | Warna Mentah Material — **tidak** lewat token tema |
| `w700` | `FontWeight.w700` |

### 0.2 Peta navigasi aplikasi

```
                       ┌──────────────────────────┐
                       │  main.dart — session?    │
                       └────────┬─────────────────┘
                valid?  ┌───────┴────────┐  tidak
          ┌─────────────┘                └──────────────┐
          ▼                                            ▼
    ┌───────────┐   biometric / password           ┌───────────┐
    │ LockScreen│◄────────────────────────────────►│ LoginScreen│
    └─────┬─────┘                                  └─────┬─────┘
          │  berhasil                                  │ "Daftar"
          ▼                                            ▼
    ┌─────────────────────────────────────────────────────────┐
    │                     DashboardScreen                     │
    │  AppBar + OfflineBanner + FAB SOS + NavigationBar(5)  │
    └──────┬───────────┬───────────┬───────────┬────────────┘
           │ 0         │ 1         │ 2         │ 3         4
           ▼           ▼           ▼           ▼           ▼
      ┌─────────┐ ┌───────────┐┌──────────┐┌──────────┐ ┌──────────┐
      │ HomeTab │ │FeatureMenu││FeatureMenu││FeatureMenu│ │ProfileTab│
      │         │ │ matches   ││activities││  tools   │ │          │
      └────┬────┘ └─────┬─────┘└────┬─────┘└────┬─────┘ └────┬─────┘
           │            │           │           │            │
           │            │           │           │            ├─► FeedbackScreen
           │            │           │           │            └─► confirmAndLogout (dialog)
           │            │           │           │
           │            │           │           └─► PunditScreen · LensScreen · AwayDayScreen
           │            │           └─► PassportScreen · PenaltyScreen · GameScreen
           │            └─► MatchCenterScreen · PredictionScreen · StadiumPointerScreen
           │                  └─► ReminderSettingsScreen · TeamPickerScreen
           └─► AwayDayScreen · CardCollectionScreen · PenaltyScreen · GameScreen
                 └─► StadiumPointerScreen · PunditScreen · PredictionScreen
```

### 0.3 Halaman yang didokumentasikan

| # | Halaman | File |
|---|---|---|
| 1 | Login | `lib/features/auth/presentation/login_screen.dart` |
| 2 | Daftar Akun | `lib/features/auth/presentation/register_screen.dart` |
| 3 | Aplikasi Terkunci | `lib/features/auth/presentation/lock_screen.dart` |
| 4 | Keluar (dialog) | `lib/features/auth/presentation/logout_flow.dart` |
| 5 | Dashboard (shell) | `lib/features/dashboard/presentation/dashboard_screen.dart` |
| 6 | Beranda | `lib/features/dashboard/presentation/home_tab.dart` |
| 7 | Menu Pertandingan | `lib/features/dashboard/presentation/feature_menu_tab.dart` |
| 8 | Menu Seru-seruan | (file yang sama, section `activities`) |
| 9 | Menu Alat Bantu | (file yang sama, section `tools`) |
| 10 | Profil | `lib/features/dashboard/presentation/profile_tab.dart` |
| 11 | Kesan & Pesan | `lib/features/dashboard/presentation/feedback_screen.dart` |
| 12 | Match Center | `lib/features/football/presentation/match_center_screen.dart` |
| 13 | Pengingat Kickoff | `lib/features/football/presentation/reminder_settings_screen.dart` |
| 14 | Pilih Tim Favorit | `lib/features/football/presentation/team_picker_screen.dart` |
| 15 | Koleksi Kartu | `lib/features/gamification/presentation/card_collection_screen.dart` |
| 16 | Paspor Suporter | `lib/features/gamification/presentation/passport_screen.dart` |
| 17 | Refleks Kiper | `lib/features/gamification/presentation/game_screen.dart` |
| 18 | Overlay Kartu Baru | `lib/features/gamification/presentation/widgets/card_reveal_overlay.dart` |
| 19 | Away Day | `lib/features/away_day/presentation/away_day_screen.dart` |
| 20 | Scan Struk & Tiket | `lib/features/lens/presentation/lens_screen.dart` |
| 21 | Pundit AI | `lib/features/pundit/presentation/pundit_screen.dart` |
| 22 | Prediksi Skor | `lib/features/prediction/presentation/prediction_screen.dart` |
| 23 | Penalty Shootout | `lib/features/penalty_shootout/presentation/penalty_screen.dart` |
| 24 | SOS Darurat | `lib/features/sos_emergency/presentation/sos_screen.dart` |
| 25 | Kompas Stadion | `lib/features/stadium_pointer/presentation/stadium_pointer_screen.dart` |

---

# 1. Design System

Fondasi visual seluruh aplikasi. Semua angka di sini berasal dari 4 file:

```
lib/core/theme/
├── app_colors.dart   (39 baris)  — palet hex mentah
├── app_theme.dart    (270 baris) — perakitan ColorScheme + TextTheme + override komponen
├── app_tokens.dart   (108 baris) — skala jarak, radius, dan ThemeExtension FanzoneColors
└── theme_provider.dart (40 baris) — penyimpanan pilihan tema pengguna
```

## 1.1 Arsitektur tema

```
MaterialApp
├── theme      → AppTheme.light          (app_theme.dart:22)
├── darkTheme  → AppTheme.dark           (app_theme.dart:25)
└── themeMode  → themeModeProvider       (main.dart:70,79)
                    └── ThemeModeNotifier → Hive box 'cache', key 'theme_mode'
                        nilai disimpan sebagai String .name: "system" | "light" | "dark"
                        default bila key hilang/tidak dikenal → ThemeMode.system
```

> **Perilaku:** `AppTheme.light` dan `AppTheme.dark` adalah **getter**, bukan `const`.
> Setiap akses membangun objek `ThemeData` baru (`app_theme.dart:22,25`).

## 1.2 Palet warna mentah — `AppColors` (`app_colors.dart`)

### Mode gelap

| Konstanta | Hex | Baris | Peran |
|---|---|---|---|
| `bgDark` | `#0A130E` | 10 | Latar `Scaffold` |
| `surfaceDark` | `#111C16` | 11 | `scheme.surface`, `surfaceContainer`, isi kartu/chip/dialog |
| `surfaceHighDark` | `#192720` | 12 | `surfaceContainerHigh`, `fz.surfaceHigh` |
| `outlineDark` | `#2A3B32` | 13 | `scheme.outline` — border, divider, thumb switch tak aktif |
| `primaryDark` | `#4CD97B` | 14 | `scheme.primary` (hijau), `surfaceTint` |
| `onPrimaryDark` | `#06210F` | 15 | `scheme.onPrimary` |
| `accentDark` | `#FFB627` | 16 | Aksen kuning (sama dengan `accent`) |
| `onAccentDark` | `#1F1500` | 17 | Teks/ikon di atas aksen |
| `textDark` | `#E9F2EC` | 18 | `scheme.onSurface` |
| `textMutedDark` | `#A3B5AA` | 19 | `fz.textMuted` |
| `errorDark` | `#FF6B6B` | 20 | `scheme.error` |

### Mode terang

| Konstanta | Hex | Baris | Peran |
|---|---|---|---|
| `bgLight` | `#F4F6EF` | 23 | Latar `Scaffold` |
| `surfaceLight` | `#FFFFFF` | 24 | `scheme.surface`, `surfaceContainer` |
| `surfaceHighLight` | `#E9EEE4` | 25 | `surfaceContainerHigh`, `fz.surfaceHigh` |
| `outlineLight` | `#CBD5C6` | 26 | `scheme.outline` |
| `primaryLight` | `#166B3A` | 27 | `scheme.primary` (hijau tua) |
| `onPrimaryLight` | `#FFFFFF` | 28 | `scheme.onPrimary` |
| `accentLight` | `#FFB627` | 29 | Aksen kuning |
| `onAccentLight` | `#1F1500` | 30 | Teks/ikon di atas aksen |
| `accentTextLight` | `#8A5A00` | 31 | `fz.accentText` — versi gelap aman sebagai teks di terang |
| `textLight` | `#111C16` | 32 | `scheme.onSurface` |
| `textMutedLight` | `#4F6258` | 33 | `fz.textMuted` |
| `errorLight` | `#B3261E` | 34 | `scheme.error` |

### Bersama kedua mode

| Konstanta | Hex | Baris | Peran |
|---|---|---|---|
| `accent` | `#FFB627` | 37 | `scheme.secondary`, `fz.accent`, latar `FilledButton`, indikator `NavigationBar` |
| `onAccent` | `#1F1500` | 38 | `scheme.onSecondary`, `fz.onAccent` |

> Aturan yang tertulis di `app_colors.dart:6-7`: **jangan hardcode warna di widget** —
> pakai `Theme.of(context)` atau `FanzoneColors`.

## 1.3 `ColorScheme` ter-resolve (`app_theme.dart:35-64`)

Peran yang **tidak** diisi di literal `ColorScheme` memakai fallback bawaan Flutter:
`onSurfaceVariant → onSurface`, `primaryContainer → primary`, `secondaryContainer → secondary`,
`errorContainer → error`, `onXContainer → onX`.

| Peran | Terang | Gelap | Sumber |
|---|---|---|---|
| `primary` | `#166B3A` | `#4CD97B` | di-set (37) |
| `onPrimary` | `#FFFFFF` | `#06210F` | di-set (38) |
| `secondary` | `#FFB627` | `#FFB627` | di-set (39) |
| `onSecondary` | `#1F1500` | `#1F1500` | di-set (40) |
| `error` | `#B3261E` | `#FF6B6B` | di-set (41) |
| `onError` | `#FFFFFF` | `#FFFFFF` | di-set (42) |
| `surface` | `#FFFFFF` | `#111C16` | di-set (43) |
| `onSurface` | `#111C16` | `#E9F2EC` | di-set (44) |
| `onSurfaceVariant` | `#111C16` | `#E9F2EC` | **fallback** = `onSurface` |
| `surfaceContainerLowest` | `#FAFBF6` | `#0C1711` | di-set (45-46) |
| `surfaceContainerLow` | `#F8FAF3` | `#0F1B14` | di-set (47-48) |
| `surfaceContainer` | `#FFFFFF` | `#111C16` | di-set (49-50) |
| `surfaceContainerHigh` | `#E9EEE4` | `#192720` | di-set (51-52) |
| `surfaceContainerHighest` | `#F2F5EC` | `#1D2C23` | di-set (53-54) |
| `primaryContainer` | `#166B3A` | `#4CD97B` | **fallback** = `primary` |
| `onPrimaryContainer` | `#FFFFFF` | `#06210F` | fallback |
| `secondaryContainer` | `#FFB627` | `#FFB627` | **fallback** = `secondary` |
| `onSecondaryContainer` | `#1F1500` | `#1F1500` | fallback |
| `errorContainer` | `#B3261E` | `#FF6B6B` | **fallback** = `error` |
| `onErrorContainer` | `#FFFFFF` | `#FFFFFF` | fallback |
| `tertiary` / `onTertiary` | `#FFB627` / `#1F1500` | sama | **fallback** = `secondary` |
| `outline` | `#CBD5C6` | `#2A3B32` | di-set (55) |
| `outlineVariant` | `#E2E9DC` | `#22312A` | di-set (56-57) |
| `inverseSurface` | `#111C16` | `#FFFFFF` | di-set (59) |
| `onInverseSurface` | `#E9F2EC` | `#111C16` | di-set (60) |
| `inversePrimary` | `#4CD97B` | `#166B3A` | di-set (61) |
| `scrim` / `shadow` | `#000000` | `#000000` | di-set (58, 62) |
| `surfaceTint` | `#166B3A` | `#4CD97B` | di-set (63) |
| `scaffoldBackgroundColor` | `#F4F6EF` | `#0A130E` | `app_theme.dart:93` |

> **Fakta penting untuk pembacaan dokumen ini:** karena `onSurfaceVariant` = `onSurface`,
> seluruh peran "redup" bawaan M3 (label nav bar tak terpilih, ikon `ListTile`, fallback `StatTile`)
> sebenarnya tampil dengan kontras penuh. Untuk teks sekunder yang benar-benar redup,
> kode memakai `fz.textMuted`.

## 1.4 `FanzoneColors` — `ThemeExtension` (`app_tokens.dart:26-95`)

Dibaca lewat `context.fz` (`app_tokens.dart:98-107`). Melempar `Exception` bila extension tidak terpasang.

| Field | Terang | Gelap | Peran |
|---|---|---|---|
| `accent` | `#FFB627` | `#FFB627` | Aksen kuning utama |
| `onAccent` | `#1F1500` | `#1F1500` | Konten di atas aksen |
| `accentText` | `#8A5A00` | `#FFB627` | Aksen yang aman sebagai teks di atas permukaan |
| `surfaceHigh` | `#E9EEE4` | `#192720` | Permukaan sedikit lebih terang dari `surface` |
| `textMuted` | `#4F6258` | `#A3B5AA` | Teks sekunder |
| `heroGradientStart` | `#E9EEE4` | `#111C16` | Awal gradien hero |
| `heroGradientEnd` | `#F4F6EF` | `#0A130E` | Akhir gradien hero |

## 1.5 Skala jarak & radius (`app_tokens.dart`)

### Jarak — `AppSpacing`

| Token | Nilai | Baris |
|---|---|---|
| `AppSpacing.xs` | `4.0` | 6 |
| `AppSpacing.sm` | `8.0` | 8 |
| `AppSpacing.md` | `12.0` | 9 |
| `AppSpacing.lg` | `16.0` | 10 |
| `AppSpacing.xl` | `24.0` | 11 |
| `AppSpacing.xxl` | `32.0` | 12 |

### Radius — `AppRadius`

| Token | Nilai | Baris | Digunakan di |
|---|---|---|---|
| `AppRadius.sm` | `12.0` | 16 | `_ClockReadout` (Away Day) |
| `AppRadius.md` | `16.0` | 18 | `TextButton`, `DataSourceBanner` |
| `AppRadius.lg` | `20.0` | 20 | `Card`, `AppCard`, `ScrimImage` default, kartu fitur |
| `AppRadius.xl` | `28.0` | 19 | `BottomSheet` atas, header `ScrimImage` |
| `AppRadius.pill` | `999.0` | 21 | Bentuk kapsul (progress bar, rarity chip) |

## 1.6 Tipografi (`app_theme.dart:240-269`)

Dua keluarga font:

| Keluarga | File | Digunakan untuk |
|---|---|---|
| `BarlowCondensed` | `BarlowCondensed-SemiBold.ttf` (w600), `BarlowCondensed-Bold.ttf` (w700) | Judul / display |
| `Inter` | `Inter-Regular.ttf` (w400), `Inter-Medium.ttf` (w500), `Inter-SemiBold.ttf` (w600) | Teks isi / label |

### Peran `TextTheme`

| Peran | Font | Size | Weight | Baris |
|---|---|---|---|---|
| `displaySmall` | BarlowCondensed | — (tidak di-set) | w700 | 242-243 |
| `headlineLarge` | BarlowCondensed | 32 | w700 | 244-245 |
| `headlineMedium` | BarlowCondensed | 28 | w600 | 246-247 |
| `headlineSmall` | BarlowCondensed | 24 | w700 | 248-249 |
| `titleLarge` | BarlowCondensed | 22 | w700 | 250-251 |
| `titleMedium` | Inter | 16 | w600 | 252-253 |
| `titleSmall` | Inter | 14 | w500 | 254-255 |
| `bodyLarge` | Inter | 16 | w400 | 256-257 |
| `bodyMedium` | Inter | 14 | w400 | 258-259 |
| `bodySmall` | Inter | 12 | w400 | 260-261 |
| `labelLarge` | Inter | 14 | w600 | 262-263 |
| `labelMedium` | Inter | 12 | w500 | 264-265 |
| `labelSmall` | Inter | 10 | w500 | 266-267 |

- `displayLarge` dan `displayMedium` **tidak** ditema → jatuh ke Roboto 57/45 bawaan.
- Warna teks bawaan semua peran = `scheme.onSurface` (Material typography mengoverride warna, bukan geometri).
- `letterSpacing` & `height` = `null` untuk semua peran → mengikuti metrik font.

### Peran yang dipakai untuk apa

| Peran | Pemakaian berulang |
|---|---|
| `headlineMedium` (28/w600) | Judul layar auth, nama lawan di hero beranda |
| `headlineSmall` (24/w700) | Judul `AppBar`, judul seksi header, nominal total, nama klub di header |
| `titleLarge` (22/w700) | `SectionHeader`, nilai `StatTile`, judul sheet, nama klub |
| `titleMedium` (16/w600) | Nama tim, judul kartu, nama fitur, poin peringkat |
| `titleSmall` (14/w500) | Label kartu, nama-short klub, waktu kickoff baris pertama |
| `bodyLarge` (16/w400) | Judul `SettingsTile`, teks analisis Pundit, isi gelembung chat |
| `bodyMedium` (14/w400) | Paragraf, deskripsi, pesan status |
| `bodySmall` (12/w400) | Keterangan, subjudul, catatan kaki, label chip |
| `labelLarge` (14/w600) | Label tombol, judul seksi pengaturan |
| `labelMedium` (12/w500) | Label `PillBadge`, label chip |
| `labelSmall` (10/w500) | Label metrik game, catatan kaki tabel |

## 1.7 Override komponen Material (`app_theme.dart:89-235`)

| Komponen | Nilai yang di-set | Baris |
|---|---|---|
| **AppBar** | `centerTitle: false`, `elevation: 0`, `scrolledUnderElevation: 0`, `backgroundColor: Colors.transparent`, `foregroundColor: scheme.onSurface`, `titleTextStyle` = `headlineSmall` + BarlowCondensed + w700 + `onSurface` (24 px) | 97-108 |
| **Card** | `elevation: 0`, `color: scheme.surface`, `margin: EdgeInsets.zero`, `clipBehavior: Clip.antiAlias`, radius `AppRadius.lg` (20), `side: BorderSide(scheme.outline, 1)` | 109-118 |
| **NavigationBar** | `height: 68`, `backgroundColor: scheme.surface`, `indicatorColor: scheme.secondary` (kuning), `indicatorShape: StadiumBorder()`, `labelBehavior: alwaysShow`; label terpilih `labelMedium`+w600+`onSurface`, tak terpilih `onSurfaceVariant`; ikon terpilih `onSecondary`, tak terpilih `onSurfaceVariant` | 119-142 |
| **FilledButton** | `minimumSize: Size(48,48)`, radius `14`, `backgroundColor: scheme.secondary` (kuning), `foregroundColor: scheme.onSecondary` | 143-150 |
| **OutlinedButton** | `minimumSize: Size(48,48)`, radius `14`, `side: BorderSide(scheme.outline, 1)` | 151-157 |
| **TextButton** | `foregroundColor: scheme.primary`, radius `16` (`AppRadius.md`) | 158-163 |
| **InputDecoration** | `filled: true`, `fillColor: scheme.surfaceContainerHigh`; border radius 14 tanpa sisi; `focusedBorder` `primary` 1.5; `errorBorder` `error` 1; `contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)` | 164-185 |
| **Chip** | `backgroundColor: scheme.surfaceContainerHigh`, `labelStyle: labelMedium`+`onSurface`, `shape: StadiumBorder()`, `side: BorderSide(scheme.outline, 1)` | 186-193 |
| **Dialog** | `backgroundColor: scheme.surface`, radius `24` | 194-199 |
| **BottomSheet** | `backgroundColor: scheme.surface`, radius atas `28` (bawah 0), `showDragHandle: true` | 200-206 |
| **SnackBar** | `behavior: floating`, radius `14`; warna latar = `inverseSurface`, teks = `onInverseSurface` | 207-212 |
| **Switch** | thumb terpilih `onSecondary`, tak terpilih `outline`; track terpilih `secondary`, tak terpilih `surfaceContainerHigh`; geometri M3: track 52×32, durasi 300 ms | 213-226 |
| **ListTile** | `iconColor: scheme.onSurfaceVariant` (= `onSurface`), `textColor: scheme.onSurface` | 227-230 |
| **Divider** | `color: scheme.outline`, `thickness: 1` | 231-234 |

> **Fakta:** warna latar `SnackBar` gelap di mode terang (`inverseSurface` = `#111C16`) dan putih di mode gelap.

## 1.8 Aset gambar (`lib/core/ui/app_images.dart`)

| Konstanta | Path | Ukuran | Pemakaian |
|---|---|---|---|
| `AppImages.gameGoal` | `assets/images/game_goal.webp` | 75 854 B | Papan gawang Refleks Kiper & Penalty |
| `AppImages.heroMalamLaga` | `assets/images/hero_malam_laga.webp` | 12 816 B | Hero beranda |
| `AppImages.headerLaga` | `assets/images/header_laga.webp` | 26 548 B | Header tab Pertandingan, header Profil, header Paspor |
| `AppImages.headerSeru` | `assets/images/header_seru.webp` | 23 374 B | Header tab Seru-seruan |
| `AppImages.headerAlat` | `assets/images/header_alat.webp` | 20 162 B | Header tab Alat Bantu |
| `AppImages.bgLogin` | `assets/images/bg_login.webp` | 38 186 B | Latar Login / Daftar / Kunci |

Aset lain: `assets/data/pl_clubs.json` (20 klub + warna + koordinat stadion),
`assets/icon/app_icon.png` · `app_icon.jpg`.

---

# 2. Pustaka Komponen Bersama

12 komponen dipakai lintas fitur. Semuanya berada di `lib/core/ui/` dan `lib/core/widgets/`.

## 2.1 `AppCard` — `lib/core/ui/app_card.dart:10-42`

Wadah kartu seragam. `Card` + `Padding`.

| Parameter | Tipe | Default |
|---|---|---|
| `child` | `Widget` | wajib |
| `onTap` | `VoidCallback?` | `null` |
| `padding` | `EdgeInsets` | `EdgeInsets.all(AppSpacing.lg)` = 16 |

- Radius `20` (`AppRadius.lg`), garis `1 px scheme.outline`, elevasi 0, warna `scheme.surface`.
- Bila `onTap != null` dibungkus `InkWell(borderRadius: 20)` — `InkWell` berada **di luar** `Card`,
  sehingga riak splash tertutup permukaan kartu opak (`app_card.dart:36-40`).
- Turunan yang memakai padding berbeda: `StatTile` → 12 · `SettingsSection` → `EdgeInsets.zero`.

## 2.2 `ScrimImage` — `lib/core/ui/scrim_image.dart:13-108`

Gambar header dengan scrim gelap bertingkat di bagian bawah.

| Parameter | Tipe | Default |
|---|---|---|
| `assetPath` | `String` | wajib |
| `child` | `Widget?` | `null` |
| `height` | `double?` | `null` (tinggi ikut parent) |
| `borderRadius` | `double` | `AppRadius.lg` = 20 |
| `fallbackColors` | `List<Color>?` | `null` → `[heroGradientStart, heroGradientEnd]` |
| `scrim` | `double` | `0.6` |
| `showPitchPattern` | `bool` | `false` |

Susunan `Stack` (urutan bawah → atas):
1. `Image.asset(fit: BoxFit.cover, cacheWidth: (lebar layar × dpr).round(), gaplessPlayback: true, excludeFromSemantics: true)`
2. Gradien scrim `Colors.black` alpha `0 → scrim` (atas → bawah)
3. `PitchPattern` (bila aktif) — digambar **di atas** scrim
4. `child`

- `errorBuilder` → `Container` dengan gradien vertikal `fallbackColors`.
- Dibatasi `ClipRRect(BorderRadius.circular(borderRadius))`.

## 2.3 `PillBadge` — `lib/core/ui/pill_badge.dart:24-94`

Lencana kapsul untuk status singkat.

| Parameter | Tipe | Default |
|---|---|---|
| `label` | `String` | wajib |
| `icon` | `Widget?` | `null` |
| `tone` | `PillTone` | `PillTone.neutral` |

| Nada | Latar | Teks | Baris |
|---|---|---|---|
| `neutral` | `scheme.surfaceContainerHigh` | `scheme.onSurface` | 56-59 |
| `accent` | `fz.accent` `#FFB627` | `fz.onAccent` `#1F1500` | 48-51 |
| `success` | `scheme.primary` | `scheme.onPrimary` | 52-55 |

Bentuk: `StadiumBorder(side: BorderSide(scheme.outline, 1))`, padding `horizontal 12 / vertical 4`,
label `labelMedium` satu baris + ellipsis, jarak ikon 4.

## 2.4 `SectionHeader` — `lib/core/ui/section_header.dart:7-45`

`Row` → `Expanded(Text(title, titleLarge, maxLines: 1, ellipsis))` + opsional `TextButton(actionLabel)`.
Tanpa padding sendiri — jarak disediakan pemanggil.

## 2.5 `StatTile` — `lib/core/ui/stat_tile.dart:11-85`

Kartu angka ringkas. `AppCard(padding: 12)` di dalam `Semantics(button: onTap != null, label: 'label: value, detail')`.

| Bagian | Gaya |
|---|---|
| Ikon (opsional) | `Padding(bottom: 4)` + `IconTheme(color: scheme.primary)` |
| Nilai | `FittedBox(scaleDown, centerLeft)` + `titleLarge` (22/w700) — menyusut otomatis agar 1 baris |
| Label | `bodySmall` |
| Keterangan | `bodySmall` + `fz.textMuted`, max 2 baris |

## 2.6 `SettingsSection` & `SettingsTile` — `lib/core/ui/settings_section.dart`

**`SettingsSection`** (`11-59`): `Column` → judul `labelLarge` + `fz.textMuted` (jarak bawah 8)
→ `AppCard(padding: EdgeInsets.zero)` → baris-baris dipisah `Divider(height: 1, indent: 56)`.

**`SettingsTile`** (`66-134`):

| Parameter | Tipe | Default |
|---|---|---|
| `icon` | `Widget` | wajib |
| `title` | `String` | wajib |
| `subtitle` | `String?` | `null` |
| `trailing` | `Widget?` | `null` |
| `onTap` | `VoidCallback?` | `null` |
| `destructive` | `bool` | `false` |

- `ConstrainedBox(minHeight: 56)` → `ListTile`.
- `contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)`.
- Ikon: `scheme.primary`, atau `scheme.error` bila `destructive`.
- Judul: `bodyLarge` (16/w400), warna `scheme.error` bila `destructive`.
- Subjudul: `bodySmall`, maksimum 3 baris.

## 2.7 `PitchPattern` — `lib/core/ui/pitch_pattern.dart:8-54`

Ornamen lapangan: `RepaintBoundary > IgnorePointer > CustomPaint(_PitchPainter, Size.infinite)`.

- `Paint`: `Colors.white.withValues(alpha: 0.08)`, `strokeWidth: 1`, `PaintingStyle.stroke`.
- Garis tengah horizontal, lingkaran tengah radius `width × 0.08`, kotak penalti `width × 0.4` × `height × 0.25` menempel tepi bawah.
- `shouldRepaint` → `false` (statis, tanpa animasi).

## 2.8 `EmptyState` — `lib/core/widgets/empty_state.dart:3-45`

| Parameter | Tipe | Default |
|---|---|---|
| `icon` | `IconData` | wajib |
| `title` | `String` | wajib |
| `message` | `String?` | `null` |
| `action` | `Widget?` | `null` |

`Center > SingleChildScrollView(padding: 32) > Column(min)`:
ikon `64 px` warna `scheme.outline` → jarak 12 → judul `titleMedium` (pusat) → jarak 4 →
pesan `TextStyle(color: scheme.outline)` (tanpa peran TextTheme) → jarak 16 → `action`.

## 2.9 `OfflineBanner` — `lib/core/widgets/offline_banner.dart:10-32`

- Sumber status: `onlineProvider` (`StreamProvider.autoDispose<bool>`, timeout 3 detik, cek ulang tiap 10 detik).
- Saat online → `SizedBox.shrink()` (tanpa celah).
- Saat offline → `Container(width: infinity, color: scheme.errorContainer, padding: horizontal 16 / vertical 8)`
  → `Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer)` → jarak 8 →
  `Text('Mode offline - menampilkan data tersimpan', color: scheme.onErrorContainer)`.
- Karena `errorContainer` = `error`, banner tampil merah pekat dengan teks putih di kedua mode.

## 2.10 `PermissionGate` — `lib/core/widgets/permission_gate.dart:6-46`

- `permissionKey`, `icon`, `title`, `message`, `child` — semua wajib.
- Bila key sudah pernah disetujui (`permissionRationaleProvider`) → `child` dirender langsung.
- Bila belum: `Center > Padding(32) > Column(min)` → ikon `64 px` (tanpa override warna) → 12 →
  judul `titleMedium` → 8 → pesan (tanpa style) → 20 → `FilledButton('Lanjutkan')`.
- Helper `confirmPermission(...)` menampilkan `AlertDialog` dengan `TextButton('Batal')` + `FilledButton('Lanjutkan')`.

## 2.11 `ClubCrest` — `lib/features/football/presentation/club_crest.dart:13-77`

| Parameter | Tipe | Default |
|---|---|---|
| `crestUrl` | `String?` | wajib |
| `tla` | `String` | wajib |
| `color` | `Color?` | `null` |
| `size` | `double` | `40` |

- `Image.network(fit: BoxFit.contain)` di `SizedBox(size × size)`.
- Fallback `_Badge`: lingkaran `size × size`, latar `color ?? scheme.surfaceContainerHighest`,
  teks `tla` `fontSize: size × 0.3`, `FontWeight.bold` (bukan Inter — `TextStyle` tanpa `fontFamily`),
  warna `scheme.onSurface` bila tanpa warna klub, else `Colors.white`/`Colors.black` menurut `estimateBrightnessForColor`.
- Fallback dipakai saat URL kosong, gagal dimuat, atau frame belum siap.

## 2.12 Komponen khusus fitur

| Komponen | File | Catatan visual |
|---|---|---|
| `DataSourceBanner` | `football/presentation/data_source_banner.dart:14-79` | `Card` radius 16 (**tanpa garis outline** karena `shape` menimpa tema) · padding `horizontal 12 / vertical 8` · ikon 16 · teks `bodySmall`. Nada: `sample` = `errorContainer` + `Icons.science`; `cache` = `secondaryContainer` + `Icons.history`; `live` = `secondaryContainer` + `Icons.cloud_done` |
| `KickoffTimes` | `football/presentation/kickoff_times.dart:5-32` | `titleSmall`+bold "Sen, 04 Okt • 02:30 WIB" (2 px jarak) + `bodySmall` "WITA 03:30 • WIT 04:30 • London 19:30". `light: true` → `Colors.white` |
| `SosHoldButton` | `sos_emergency/presentation/sos_hold_button.dart:14-83` | `Semantics > Listener > AnimatedBuilder > SizedBox(size) > Stack`. Lingkaran merah `Colors.red` dengan `margin: EdgeInsets.all(4)`, teks "SOS" `fontSize: size × 0.28` bold putih, cincin `CircularProgressIndicator(strokeWidth: 5)` putih. Durasi tahan 3 detik. Default `size: 64`, dipakai `200` di layar SOS |
| `FeatureCard` / `FeaturedFeatureCard` | `dashboard/presentation/feature_cards.dart` | `_featureIcon` = lingkaran 48 px gradien `primary → lerp(primary, accent, 0.5)`, ikon 24 px `onPrimary`. Kartu grid padding 12, kartu unggulan padding 16 |
| `CardRevealOverlay` | `gamification/presentation/widgets/card_reveal_overlay.dart` | Overlay `showGeneralDialog`, barrier `Colors.black54`, transisi 200 ms; kartu 220 × 320, radius 20; flip `rotateY` 900 ms + denyut 400 ms |

---

# 3. Konvensi Layout Lintas Halaman

## 3.1 Pola kerangka halaman

Empat kerangka berulang di seluruh aplikasi.

### Pola A — Shell dengan tab (Dashboard)

```
Scaffold
├── appBar: AppBar (judul per tab + tombol alih tema)
├── body: Column
│   ├── OfflineBanner
│   └── Expanded(IndexedStack(5 halaman))
├── floatingActionButton: SosHoldButton(64)
└── bottomNavigationBar: NavigationBar(5 tujuan, height 68)
```

### Pola B — Halaman daftar/isi dengan AppBar

```
Scaffold
├── appBar: AppBar (judul + aksi opsional + TabBar opsional)
└── body: Center
    └── ConstrainedBox(maxWidth: 720)
        └── ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 104))
```

`104` di bawah = ruang untuk `NavigationBar` (68) + FAB SOS (64).

### Pola C — Halaman berisi form/dialog

```
Scaffold
├── appBar: AppBar (judul)
└── body: Center
    └── ConstrainedBox(maxWidth: 720)
        └── ListView(padding: EdgeInsets.all(16))
```

### Pola D — Layar auth (latar gambar penuh)

```
Scaffold
└── body: Stack(fit: expand)
    ├── ScrimImage(bgLogin, borderRadius: 0, scrim: 0.7, showPitchPattern: true)
    └── SafeArea
        └── Center
            └── SingleChildScrollView(padding: 24)
                └── ConstrainedBox(maxWidth: 420)
                    └── Column
```

## 3.2 Pola responsif

| Ambang | Perilaku | Lokasi |
|---|---|---|
| `< 600` | Grid fitur 2 kolom; item pertama dijadikan **kartu unggulan** baris penuh | `feature_menu_tab.dart:47-56` |
| `600 – 899` | Grid fitur 3 kolom, semua item di grid | `feature_menu_tab.dart:50-52` |
| `≥ 900` | Grid fitur 4 kolom | `feature_menu_tab.dart:50-52` |
| `> 600` (lebar konten) | Grid kartu koleksi 3 kolom (selain 2) | `card_collection_screen.dart:158` |
| `maxWidth: 720` | Batas lebar konten LIST dan FORM | 14 halaman |
| `maxWidth: 420` | Batas lebar form auth | 3 halaman auth |
| Tanpa batas | `StadiumPointerScreen` (peta memenuhi lebar) | `stadium_pointer_screen.dart` |

## 3.3 Pola padding

| Konteks | Padding |
|---|---|
| Shell tab (Home, Menu, Profil) | `EdgeInsets.fromLTRB(16, 8, 16, 104)` |
| Halaman push (Match Center, Away Day, Lens, dst.) | `EdgeInsets.all(16)` atau `fromLTRB(16, 8, 16, 104)` |
| Form auth | `EdgeInsets.all(24)` |
| Header `ScrimImage` | `EdgeInsets.all(16)` |
| Kartu (default `AppCard`) | `EdgeInsets.all(16)` |
| Kartu padat (StatTile, kartu fitur grid, kartu match) | `EdgeInsets.all(12)` |
| Kartu tanpa padding (grup `SettingsSection`, kartu championship) | `EdgeInsets.zero` |
| Pemisah seksi | `SizedBox(height: 24)` (`AppSpacing.xl`) |
| Pemisah kartu dalam satu seksi | `SizedBox(height: 12)` (`AppSpacing.md`) |
| Pemisah label | `SizedBox(height: 8)` (`AppSpacing.sm`) |
| Pemisah ikon–teks | `SizedBox(height: 4)` (`AppSpacing.xs`) |

## 3.4 Skala teks & `textScaler`

Pola clamping yang dipakai seragam di seluruh app:

```dart
final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
```

|Clipping| | | Pemakaian |
|---|---|---|
| `feature_menu_tab.dart:48, 108` | tinggi banner `170 × scale` | tinggi kartu grid `176 × scale` |
| `home_hero.dart` | tinggi hero `260 × scale` | |
| `upcoming_matches.dart:54` | tinggi daftar `120 × scale` | |
| `cards_teaser.dart` | — | |
| `profile_header.dart:51-53` | tinggi header `230 × scale` | |
| `passport_screen.dart:88-90` | tinggi header `190 × scale` | |
| `card_collection_screen.dart:106` | tinggi kartu `196 × scale` | |

Konsekuensi: pada skala teks 1.5, tinggi banner menu = 255 px, tinggi kartu grid = 264 px,
tinggi kartu koleksi = 294 px.

## 3.5 Pola state yang dipakai

| State | Pola visual |
|---|---|
| Loading | `Center(CircularProgressIndicator())` polos, **tanpa teks** |
| Loading (partial) | `LinearProgressIndicator` setinggi 40 (`AwayDayScreen:268`), atau strip 2 px di bawah tombol (`lens_screen.dart:143`) |
| Error | `Center(Text(e.toString().replaceFirst('Exception: ', '')))` polos, tanpa aksi ulang |
| Error (dengan aksi) | `EmptyState(icon: Icons.error_outline, action: FilledButton('Coba lagi'))` |
| Empty | `EmptyState` inti (ikon 64 + judul + pesan) atau `AppCard` teks ajakan |
| Empty (kosong diam) | `SizedBox.shrink()` — komponen disembunyikan sepenuhnya |
| Offline | `OfflineBanner` merah full-bleed di bawah AppBar |
| Sukses | `SnackBar` mengambang radius 14, warna `inverseSurface` |

> Catatan: halaman `MatchCenterScreen` (tab Klasemen/Top Skor) dan `TeamPickerScreen`
> memakai `Center(Text(...))` untuk error — **tanpa** `EmptyState` atau tombol coba lagi.

## 3.6 Pola interaksi

| Pola | Perilaku |
|---|---|
| Aksen utama | `FilledButton` → latar **kuning** `scheme.secondary`, teks `onSecondary` |
| Aksen sekunder | `OutlinedButton` → garis `scheme.outline` 1 px |
| Aksi teks | `TextButton` → warna `scheme.primary` (hijau) |
| Pilihan | `ChoiceChip` / `FilterChip` / `InputChip` / `Chip` — semua bentuk kapsul |
| Kartu bisa diketuk | `AppCard(onTap:)` → `InkWell` radius 20 |
| Hapus | `Dismissible` `endToStart` dengan latar `errorContainer` (Away Day) atau `IconButton` hapus (yang lain) |
| Snackbar | `ScaffoldMessenger.showSnackBar` → mengambang, radius 14 |

---

# 4. Dokumentasi Per Halaman

> Setiap halaman ditulis dengan pola yang sama:
> **Struktur** (peta widget) · **Metrik layout** · **Warna** · **Tipografi** ·
> **Komponen** · **Ikon** · **State** · **Catatan**.
> Nomor `[1]`, `[2]`, … pada bagian Struktur mengikuti penomoran blok
> pada komentar `// STRUKTUR UI` di file sumber.

## 4.1 Auth

### 4.1.1 Login — `lib/features/auth/presentation/login_screen.dart` (184 baris)

`LoginScreen extends ConsumerStatefulWidget` (23) · `_LoginScreenState` (29).

**Struktur**

```
Scaffold                                                        L63
└─ body: Stack(fit: expand)                                     L64
   ├─ ScrimImage(bgLogin, radius 0, scrim 0.7, pattern)         L67-72
   └─ SafeArea → Center → SingleChildScrollView                  L73-75
      └─ ConstrainedBox(maxWidth: 420) → Column                  L77-79
         ├─ [1] Bundar 88×88 + Icon(Icons.sports_soccer, 44)     L81-91
         ├─ SizedBox(16)                                          L92
         ├─ [2] "Ultimate Fanzone" (headlineMedium)               L93-97
         │     SizedBox(4)                                        L98
         │     "Teman suporter Premier League-mu" (bodyMedium)    L99-104
         ├─ SizedBox(24)                                          L105
         └─ [3] AppCard → Column(stretch)                        L106-173
               ├─ TextField 'Email'                               L110-115
               ├─ SizedBox(16)                                    L116
               ├─ TextField 'Password' + suffixIcon              L117-130
               ├─ SizedBox(24)                                    L131
               ├─ FilledButton 'Masuk' / spinner 20×20 sw2        L132-145
               ├─ SizedBox(12) + OutlinedButton.icon biometrik    L146-157
               └─ SizedBox(4) + TextButton 'Belum punya akun? Daftar'  L158-170
```

**Metrik layout**

| Elemen | Nilai |
|---|---|
| Padding scroll | `EdgeInsets.all(24)` (L76) |
| Lebar maks | `420` (L78) |
| Bundar logo | `88 × 88`, `BoxShape.circle` (L82-87) |
| Jarak logo→judul | 16 (L92) · judul→subjudul 4 (L98) · subjudul→kartu 24 (L105) |
| Jarak field | email→password 16 (L116) · password→Masuk 24 (L131) |
| Jarak tombol | Masuk→biometrik 12 (L147) · biometrik→tautan 4 (L158) |
| Spinner | `20 × 20`, `strokeWidth: 2` (L139-143) |

**Warna**

| Elemen | Sumber | Ter-resolve |
|---|---|---|
| Bundar bola | `fz.accent` | `#FFB627` |
| Ikon bola | `fz.onAccent` | `#1F1500` |
| Judul | `Colors.white` (mentah) | `#FFFFFF` |
| Subjudul | `Colors.white70` (mentah) | `#B3FFFFFF` |
| Latar | gradien hitam `0 → 0.7` + pitch putih α 0.08 | |
| Isi form | `surfaceContainerHigh` | terang `#E9EEE4` / gelap `#192720` |
| Tombol Masuk | `scheme.secondary` / `onSecondary` | `#FFB627` / `#1F1500` |
| Tautan daftar | `scheme.primary` | terang `#166B3A` / gelap `#4CD97B` |

**Tipografi** · judul `headlineMedium` + `copyWith(color: Colors.white)` · subjudul `bodyMedium` + `Colors.white70` · label tombol `labelLarge` (bawaan FilledButton).

**Komponen** · `ScrimImage` · `AppCard` (padding default 16).

**Ikon** · `Icons.sports_soccer` (44) · `Icons.visibility` / `Icons.visibility_off` (24) · `Icons.fingerprint` (24).

**State**

| State | Tampilan |
|---|---|
| Loading | `authProvider.isLoading` → tombol Masuk nonaktif + spinner 20 px; tombol biometrik & tautan ikut nonaktif |
| Error | `SnackBar(describeAuthError(e))` |
| Sukses | `Navigator.pushReplacement(DashboardScreen)` |
| Biometrik mati | Blok tombol biometrik tidak dirender (`biometricEnabledProvider`) |

---

### 4.1.2 Daftar Akun — `lib/features/auth/presentation/register_screen.dart` (180 baris)

`RegisterScreen extends ConsumerStatefulWidget` (26) · `_RegisterScreenState` (33).

**Struktur** — sama dengan Login, ditambah `AppBar(title: 'Daftar Akun')` (L68).

```
Scaffold + AppBar('Daftar Akun')                                 L67-68
└─ body: Stack → ScrimImage → SafeArea → Center
   └─ SingleChildScrollView(24) → ConstrainedBox(420) → Column   L79-84
      ├─ [1] Bundar 88×88 + Icon(Icons.sports_soccer, 44)          L86-96
      ├─ SizedBox(16)                                              L97
      ├─ [2] "Ultimate Fanzone" (headlineMedium)                   L98-102
      ├─ SizedBox(24)                                              L103
      └─ [3] AppCard → Column(stretch)                            L104-169
            ├─ TextField 'Email' + helperText                      L108-117
            ├─ SizedBox(16)                                        L118
            ├─ TextField 'Password' + helperText + suffixIcon      L119-133
            ├─ SizedBox(16)                                        L134
            ├─ TextField 'Ulangi password'                         L135-141
            ├─ SizedBox(24)                                        L142
            ├─ FilledButton 'Daftar' / spinner                      L143-159
            └─ SizedBox(8) + TextButton 'Sudah punya akun? Masuk'  L160-166
```

**Perbedaan dari Login**

| Aspek | Login | Daftar |
|---|---|---|
| AppBar | Tidak ada | `AppBar('Daftar Akun')` |
| Subjudul | Ada (`bodyMedium` putih70) | Tidak ada |
| Field | 2 | 3 (+ konfirmasi) |
| Jarak ke tautan bawah | 4 | 8 (`AppSpacing.sm`) |
| Teks bantuan | Tidak ada | "Minimal 8 karakter" pada field password |

**Warna & tipografi** · sama dengan Login. `AppBar` transparan, judul `headlineSmall` (24/w700) warna `onSurface`.

**State** · Loading: tombol nonaktif + spinner · Error: `SnackBar` · Sukses: `pushReplacement(DashboardScreen)`.
Validasi password **tidak** live di UI — hanya `helperText` statis (L124);真正 validasi di server.

---

### 4.1.3 Aplikasi Terkunci — `lib/features/auth/presentation/lock_screen.dart` (252 baris)

`LockScreen extends ConsumerStatefulWidget` (26) · `_PasswordDialog` (169).

**Struktur**

```
PopScope(canPop: false)                                          L89-90
└─ Scaffold                                                      L91
   └─ body: Stack → ScrimImage → SafeArea → Center
      └─ SingleChildScrollView(24) → ConstrainedBox(420) → Column L103-107
         ├─ [1] Bundar 88×88 + Icon(Icons.lock, 44)               L109-118
         ├─ SizedBox(16)                                          L119
         ├─ [2] "Aplikasi terkunci" (headlineMedium)              L120-125
         ├─ SizedBox(24)                                          L126
         └─ [3] AppCard → Column(stretch)                        L127-150
               ├─ [biometrik] FilledButton.icon 'Buka dengan Biometrik'  L131-137
               ├─ TextButton 'Gunakan password'                   L138-141
               └─ TextButton 'Keluar dari akun'                   L142-147

[4] _PasswordDialog — AlertDialog
   ├─ title: 'Masuk dengan password'
   ├─ content: TextField (obscure, autofocus) + [error] SizedBox(12) + Text(error, colorScheme.error)
   └─ actions: TextButton 'Batal' + FilledButton 'Buka' (spinner 18×18 sw2 saat busy)
```

**Metrik** · padding 24 (L104) · lebar 420 (L106) · bundar 88 (L110-115) · ikon 44 (L117) ·
jarak 16/24 (L119, L126) · dialog error gap 12 (L226) · spinner 18×18 sw2 (L242-246).

**Warna** · bundar `fz.accent` · ikon `fz.onAccent` · judul `Colors.white` ·
teks galat dialog `scheme.error` (terang `#B3261E` / gelap `#FF6B6B`).

**Tipografi** · judul `headlineMedium` + putih · judul dialog `titleLarge` (Material default) ·
**teks galat dialog memakai `TextStyle` mentah tanpa peran TextTheme** (L229).

**State**

| State | Tampilan |
|---|---|
| Awal | `initState` memicu `authProvider.notifier.unlock()` di `Future.microtask` (L39-45) → dialog biometrik terbuka otomatis |
| Loading | Ketiga tombol nonaktif; tombol dialog menampilkan spinner 18 px |
| Error provider | `SnackBar(describeAuthError(e))` |
| Error dialog | `_error` dari `describeAuthError(e)` ditampilkan di `scheme.error` di dalam dialog |
| Sukses | `popOnSuccess == true` → `Navigator.pop()` (kembali ke tab yang sama); `false` → `pushReplacement(DashboardScreen)` |

> `PopScope(canPop: false)` — tombol back sistem tidak menutup layar kunci.

---

### 4.1.4 Alur Keluar — `lib/features/auth/presentation/logout_flow.dart` (198 baris)

Bukan widget; kumpulan fungsi + `AlertDialog`.

| Fungsi | Baris | Peran |
|---|---|---|
| `logoutSyncAttemptProvider` | 33-39 | `Provider<Future<String?> Function()>` → `retryPendingPrefs()` |
| `_pendingRows(ref)` | 42-57 | daftar data yang belum tersinkron |
| `_syncAttempt(ref)` | 60-73 | mencoba sinkron dengan **timeout 15 detik** (L65) |
| `confirmAndLogout(context, ref)` | 93-103 | titik masuk: konfirmasi → `logoutProvider()` → `pushAndRemoveUntil(LoginScreen, (route) => false)` |
| `_confirmLogout(context, ref)` | 106-179 | dua dialog + percobaan ulang |

**Dialog [1] — "Keluar?"** (L127-138, saat tidak ada data tertinggal)

```
AlertDialog
├─ title: 'Keluar?'
├─ content: 'Sesi akan dihapus dari perangkat ini.'
└─ actions: TextButton 'Batal' + FilledButton 'Keluar'
```

**Dialog [2] — "Data belum dicadangkan"** (L146-165, saat masih ada data tertinggal)

```
AlertDialog
├─ title: 'Data belum dicadangkan'
├─ content: _warningText(rows, online, cause)
└─ actions: TextButton 'Batal'
             [TextButton 'Coba sinkron lagi'  — hanya bila online & belum pernah mencoba]
             FilledButton 'Keluar tetap' (backgroundColor: scheme.error)
```

**Isi peringatan** (L182-198) — baris demi baris dengan bullet `•`:
"Masih ada data yang belum terkirim ke server:" → daftar koleksi → "Kalau keluar sekarang, data itu akan dihapus dari perangkat ini dan tidak bisa dipulihkan."
Ditambah baris "Perangkat sedang offline." bila offline, dan "Penyebab: …" bila ada error sinkron.

**Warna** · `FilledButton 'Keluar'` = kuning aksen (tema) · `FilledButton 'Keluar tetap'` = `scheme.error` (merah) via `styleFrom` (L161-164).

**Tipografi** · judul `titleLarge` (BarlowCondensed 22/w700) · isi `bodyMedium` (Inter 14/w400) · tombol `labelLarge`.

**State** · Online → coba sinkron dulu (15 dtk) · Offline → langsung tampil peringatan · Retry **hanya satu kali** (tombol hilang setelah ditekan) · Sukses → sesi dihapus, seluruh stack nav dibersihkan.

---

## 4.2 Dashboard

### 4.2.1 Shell — `lib/features/dashboard/presentation/dashboard_screen.dart` (133 baris)

`DashboardScreen extends ConsumerWidget` (27).

**Struktur**

```
AutoLockObserver                                                  L71
└─ CardRevealListener                                             L72
   └─ Scaffold                                                     L73
      ├─ appBar: AppBar(title: per tab) + IconButton alih tema     L74-85
      ├─ body: Column                                              L86-91
      │  ├─ [2] OfflineBanner                                      L87
      │  └─ Expanded(IndexedStack(index, 5 halaman))               L88-90
      ├─ floatingActionButton: SosHoldButton(size: 64)             L92-95
      └─ bottomNavigationBar: NavigationBar (5 tujuan)              L96-128
```

**Isi `IndexedStack` dan judul AppBar**

| Index | Halaman | Judul AppBar |
|---|---|---|
| 0 | `HomeTab` | "Ultimate Fanzone" |
| 1 | `FeatureMenuTab(matches)` | "Pertandingan" |
| 2 | `FeatureMenuTab(activities)` | "Seru-seruan" |
| 3 | `FeatureMenuTab(tools)` | "Alat Bantu" |
| 4 | `ProfileTab` | "Profil" |

**Metrik** · `NavigationBar.height` 68 (tema) · FAB `SosHoldButton(64)` → lingkaran merah terlihat 56 × 56 (`margin: EdgeInsets.all(4)`) · `body` tanpa padding sendiri.

**Warna** · AppBar transparan, judul `onSurface` · indikator nav `scheme.secondary` (kuning) ·
ikon nav terpilih `onSecondary` (hijau tua) · ikon nav tak terpilih `onSurfaceVariant` (= `onSurface`) ·
label nav terpilih `labelMedium`+w600 · SOS `Colors.red` (mentah).

**Ikon** · `Icons.light_mode` / `Icons.dark_mode` · nav: `home_outlined`/`home`, `sports_soccer_outlined`/`sports_soccer`, `sports_esports_outlined`/`sports_esports`, `widgets_outlined`/`widgets`, `person_outline`/`person`.

**State** · Offline → banner merah muncul · Gagal baca lokasi (SOS) → `SnackBar('Gagal membaca lokasi: …')` ·
Sukses SOS → `SnackBar` pesan · Goyang HP 2× → dialog konfirmasi SOS (`shakeProvider` → `showSosConfirm`).

> `IndexedStack` menjaga kelima halaman tetap hidup, sehingga state tiap tab tidak hilang saat berpindah.

---

### 4.2.2 Beranda — `lib/features/dashboard/presentation/home_tab.dart` (60 baris)

**Struktur**

```
RefreshIndicator(onRefresh: footballRefreshProvider)                L31-32
└─ ListView (physics: AlwaysScrollableScrollPhysics)               L33-35
   └─ Center → ConstrainedBox(maxWidth: 720) → Column(stretch)     L37-40
      ├─ [1] HomeHero                                              L43
      ├─ SizedBox(24)                                              L44
      ├─ [2] QuickActions                                          L45
      ├─ SizedBox(24)                                              L46
      ├─ [3] HomeStats                                             L47
      ├─ SizedBox(24)                                              L48
      ├─ [4] UpcomingMatches                                       L49
      ├─ SizedBox(24)                                              L50
      └─ [5] CardsTeaser                                          L51
```

**Metrik** · padding `EdgeInsets.fromLTRB(16, 8, 16, 104)` (L34) · lebar 720 (L39) · 4 pemisah 24.

`home_tab.dart` sendiri tidak memuat warna maupun teks — seluruh tampilan berasal dari lima widget anak.

---

#### 4.2.2.1 `HomeHero` — `widgets/home_hero.dart`

```
Semantics(container: true)
└─ ScrimImage(heroMalamLaga, height: 260 × scale, scrim: 0.75,
              showPitchPattern: true,
              fallbackColors: [darken(warna klub, 0.65), fz.heroGradientEnd])
   └─ Stack(fit: expand)
      ├─ [klub != null] DecoratedBox → gradien horizontal
      │     (warna klub α 0.45 → α 0, kiri→kanan)
      └─ Padding(16) → Column(start)
         ├─ [2] Baris identitas klub
         │  ├─ Container(padding 2, circle, Colors.white) > ClubCrest(40)
         │  ├─ SizedBox(12)
         │  ├─ Expanded → Column(min)
         │  │  ├─ Text(nama klub, headlineSmall, putih, 1 baris)
         │  │  └─ Text('stadion · kota', bodySmall, white70, 1 baris)
         │  └─ IconButton(Icons.edit, putih, tooltip 'Ganti tim favorit')
         ├─ SizedBox(16)
         └─ [3] Blok laga berikutnya
               PillBadge('Laga berikutnya · Tactics/host')
               SizedBox(4)
               Text('vs $lawan', headlineMedium, putih, ≤2 baris)
               SizedBox(4) → FittedBox > KickoffTimes(light: true)
               SizedBox(12) → Wrap(spacing 8, runSpacing 8)
                 ├─ Row(min) → Icon(Icons.timer, 18, fz.accent) + SizedBox(4)
                 │            + Flexible(Text(hitung mundur, headlineSmall, fz.accent))
                 ├─ [opsional] PillBadge('Dini hari', accent)
                 └─ FilledButton('Prediksi')
```

**Metrik** · tinggi `260 × scale` (→ maks 390) · scrim `0.75` · gradien klub α `0.45 → 0` ·
cincin crest `padding 2` · crest `40` · gap crest→nama `12` · gap identitas→laga `16` ·
gap ikon timer→teks `4` · ikon timer `18` · spinner `28 × 28` · padding konten `16` ·
`_darken` memakai lightness HSL `0.65`.

**Warna** · nama klub `Colors.white` · stadion `Colors.white70` · ikon edit `Colors.white` ·
cincin crest `Colors.white` · hitung mundur `fz.accent` `#FFB627` · gradien klub `club.colorValue` ·
`PillBadge` netral untuk "Laga berikutnya", nada `accent` untuk "Dini hari".

**State**

| State | Tampilan |
|---|---|
| Tanpa klub | `_EmptyHero`: judul `headlineSmall` putih "Pilih tim favoritmu" → 8 → subjudul `bodyMedium` white70 → 16 → `FilledButton('Pilih tim')` → `TeamPickerScreen` |
| Loading | `Padding(vertical: 16)` → `Center` → spinner `28 × 28` |
| Error | `Row` → `Expanded(Text('Jadwal belum bisa dimuat', bodyMedium, putih))` + `TextButton('Coba lagi')` → `ref.invalidate(matchesProvider)` |
| Jadwal kosong | `Text('Belum ada laga mendatang', bodyMedium, putih)` |
| Data | Susunan blok "[3]" di atas |

---

#### 4.2.2.2 `QuickActions` — `widgets/quick_actions.dart`

```
Row → 4 × Expanded(_QuickAction)
└─ Semantics(button: true, label: label)
   └─ InkWell(customBorder: CircleBorder())
      └─ Padding(vertical: 8, horizontal: 4)
         └─ Column(min)
            ├─ Container(56 × 56, circle,
            │     color: scheme.surfaceContainerHigh,
            │     border: Border.all(scheme.outline, 1))
            │  └─ Icon(icon, color: scheme.primary)
            ├─ SizedBox(8)
            └─ Text(label, bodySmall, center, ≤2 baris, ellipsis)
```

**Metrik** · lingkaran `56 × 56` · border 1 px · padding vertikal 8 / horizontal 4 · gap ikon→label 8 · `maxLines` 2.

**Warna** · latar lingkaran `scheme.surfaceContainerHigh` (terang `#E9EEE4` / gelap `#192720`) ·
border `scheme.outline` · ikon `scheme.primary` (hijau) · label `bodySmall` `onSurface`.

**Isi** (statis, 4 pintasan)

| Label | Ikon | Tujuan |
|---|---|---|
| Prediksi | `Icons.scoreboard_outlined` | `PredictionScreen` |
| Kompas | `Icons.explore` | `StadiumPointerScreen` |
| Pundit AI | `Icons.auto_awesome` | `PunditScreen` |
| Away Day | `Icons.currency_exchange` | `AwayDayScreen` |

---

#### 4.2.2.3 `HomeStats` — `widgets/home_stats.dart`

```
Column(start)
├─ SectionHeader(title: 'Ringkasan')
├─ SizedBox(12)
└─ Row
   ├─ Expanded(StatTile 'Away Day')  → SizedBox(12)
   ├─ Expanded(StatTile 'Stempel')   → SizedBox(12)
   └─ Expanded(StatTile 'Kartu Klub')
```

**Isi tile**

| Tile | Nilai | Keterangan | onTap |
|---|---|---|---|
| Away Day | `Rp ${totals.idr.round()}` | `dari Rp ${budget}` atau "belum ada anggaran" | `AwayDayScreen` |
| Stempel | jumlah stamp | `di ${club.name}` atau "semua stadion" | `PassportScreen` |
| Kartu Klub | `${cards.length}` | `${ownedClubs} klub` | `CardCollectionScreen` |

**Metrik** · gap header→baris 12 · gutter antar-tile 12 ×2 · 3 tile `Expanded` (setiap kartu padding 12).

**State** · tidak ada cabang loading/error — provider dibaca sinkron (`valueOrNull`), sehingga angka 0 tampil selagi data belum arrives.

---

#### 4.2.2.4 `UpcomingMatches` — `widgets/upcoming_matches.dart`

```
Column(start)
├─ SectionHeader(title: 'Laga berikutnya', actionLabel: 'Lihat semua') → MatchCenterScreen
├─ SizedBox(8)
└─ SizedBox(height: 120 × scale)
   └─ ListView.separated(horizontal, maks 5 item, separator SizedBox(12))
      └─ SizedBox(width: 220) → _MatchCard
```

`_MatchCard`:

```
AppCard(onTap, padding: 12)
└─ Column(start, spaceBetween)
   ├─ Text('Sen, 04 Okt • 02:30 WIB', labelMedium, 1 baris)
   ├─ SizedBox(8)
   ├─ Row → ClubCrest(28) + SizedBox(8) + Expanded(Text(nama, bodySmall, 1 baris))
   ├─ SizedBox(4)
   └─ Row → ClubCrest(28) + SizedBox(8) + Expanded(Text(nama, bodySmall, 1 baris))
```

**Metrik** · tinggi daftar `120 × scale` · lebar kartu `220` · maks 5 item · separator 12 · padding kartu 12 · crest 28 · gap crest→nama 8 · gap antar-tim 4.

**State** · data kosong atau setelah filter kosong → **seluruh widget disembunyikan** (`SizedBox.shrink()`), bukan menampilkan empty state. Tidak ada spinner.

---

#### 4.2.2.5 `CardsTeaser` — `widgets/cards_teaser.dart`

```
Column(start)
├─ SectionHeader(title: 'Kartu Klub terbaru', actionLabel: 'Koleksi') → CardCollectionScreen
├─ SizedBox(12)
└─ Row(start) → maks 3 × Expanded(_CardTile)  (gap 12)
```

`_CardTile`:

```
AppCard(padding: 12)
└─ Column(center)
   ├─ ClubCrest(36) | _TextBadge(36) bila klub null
   ├─ SizedBox(8)
   ├─ Text(nama pendek, bodySmall, center, 1 baris)
   ├─ SizedBox(4)
   └─ PillBadge(label kelangkaan, tone: accent bila epic|legendary, selain itu neutral)
```

`_TextBadge`: `Container(36 × 36, circle, color: scheme.surfaceContainerHighest, border: Border.all(scheme.outline, 1))` → `Text(label, labelSmall)`; label = 3 huruf pertama `clubKey` uppercase, fallback `'?'`.

**Metrik** · crest / badge `36 × 36` · gap header→isi 12 · gutter antar-tile 12 · gap crest→nama 8 · gap nama→badge 4 · maks 3 tile.

**Warna** · badge latar `surfaceContainerHighest` (terang `#F2F5EC` / gelap `#1D2C23`) · border `scheme.outline` · badge kelangkaan `accent` (kuning) untuk epik & legendaris, `neutral` untuk biasa & langka.

**State** · koleksi kosong → `AppCard` (padding 16) berisi teks `bodyMedium` "Belum ada kartu. Main Adu Penalti atau tebak skor untuk mendapat kartu pertamamu." (tap → `PenaltyScreen`).

---

### 4.2.3 Menu Fitur — `lib/features/dashboard/presentation/feature_menu_tab.dart` (150 baris)

Satu file melayani **tiga** tab (Pertandingan / Seru-seruan / Alat Bantu) lewat parameter `FeatureSection`.

**Struktur**

```
ListView (padding: fromLTRB(16, 8, 16, 104))                       L58-59
└─ Center → ConstrainedBox(maxWidth: 720) → Column(stretch)        L61-64
   ├─ [1] SectionHeaderBanner(section, group)                       L67
   ├─ SizedBox(16)                                                  L68
   ├─ [2] [hanya layar sempit] FeaturedFeatureCard(item pertama)     L69-72
   └─ [3] GridView.builder                                           L73-84
        shrinkWrap: true, physics: NeverScrollableScrollPhysics
```

**Responsif**

| Lebar | `isWide` | Kolom | Item dirender |
|---|---|---|---|
| `≥ 900` | true | 4 | semua item |
| `600 – 899` | true | 3 | semua item |
| `< 600` | false | 2 | `group.items.skip(1)` — item pertama jadi kartu unggulan |

**Metrik grid** · `crossAxisSpacing` 12 · `mainAxisSpacing` 12 · `mainAxisExtent` `176 × scale` (→ maks 264).

#### `SectionHeaderBanner` (blok [1])

```
ScrimImage(asset per section,
  height: 170 × scale,          → maks 255
  borderRadius: AppRadius.xl (28),
  scrim: 0.7,
  showPitchPattern: true,
  fallbackColors: [warna fallback section, fz.heroGradientEnd])
└─ Align(bottomLeft) → Padding(16) → Column(min, start)
   ├─ Text(group.title, headlineSmall, Colors.white, 1 baris)
   ├─ SizedBox(8)
   ├─ Text(group.description, bodyMedium, Colors.white70, ≤2 baris)
   └─ PillBadge('N fitur')
```

**Warna fallback per section** (L19-27)

| Section | Warna fallback awal |
|---|---|
| `matches` | `scheme.primary` |
| `activities` | `Color.lerp(scheme.primary, fz.accent, 0.5)` |
| `tools` | `Color.lerp(scheme.primary, scheme.secondary, 0.5)` |

> Kedua lerp menghasilkan hex yang sama: terang ≈ `#8B9131`, gelap ≈ `#A6C851`.

#### Kartu fitur

| Varian | Padding | Susunan | Ikon |
|---|---|---|---|
| `FeaturedFeatureCard` (baris penuh, layar sempit) | 16 | `Row`: ikon 48 · 16 · `Column`(label + badge / 4 / deskripsi) · 8 · chevron | `Container(48 × 48, circle)` gradien `primary → lerp(primary, accent, 0.5)`, ikon 24 `onPrimary` |
| `FeatureCard` (grid) | 12 | `Column`: `Row`(ikon 48 + badge) · 12 · label · 4 · deskripsi (`Expanded`) | sama |

`maxLines`: label 2, deskripsi 3. Deskripsi memakai `bodySmall` + `fz.textMuted`.
Aksesibilitas: `Semantics(button: true, label: 'label. deskripsi', excludeSemantics: true)`.

#### Registry menu — `menu_groups.dart`

Tiap grup berisi tepat 3 item; total 2 badge.

| Tab | Judul | Deskripsi | Item |
|---|---|---|---|
| `matches` | Pertandingan | "Ikuti laga, susun prediksi, dan temukan arah ke stadion." | Match Center · Prediksi Skor · Kompas Stadion |
| `activities` | Seru-seruan | "Kumpulkan pencapaian dan uji keterampilanmu." | Paspor Suporter · Penalty Shootout · Refleks Kiper |
| `tools` | Alat Bantu | "Asisten pintar, pemindai harga, dan rencana away day." | Pundit AI *(badge "AI")* · Scan Struk & Tiket *(badge "Kamera")* · Away Day |

---

### 4.2.4 Profil — `lib/features/dashboard/presentation/profile_tab.dart` (77 baris)

**Struktur**

```
ListView (padding: fromLTRB(16, 8, 16, 104))                        L55-56
└─ ConstrainedBox(maxWidth: 720) → Column                           L58-60
   ├─ [1] ProfileHeader(email, photoPath, onChoosePhoto)            L62-66
   ├─ SizedBox(24)                                                  L67
   ├─ [2] ProfileStats                                              L68
   ├─ SizedBox(24)                                                  L69
   └─ [3] ProfileSections                                           L70
```

> **Catatan:** `ProfileTab` **tidak** membungkus `ConstrainedBox` dengan `Center`
> (berbeda dengan `HomeTab` L37 dan `FeatureMenuTab` L61). Pada layar lebar,
> kolom konten menempel ke kiri.

**Bottom sheet [4] — pilih sumber foto** (L24-48)

```
showModalBottomSheet<ImageSource>
└─ SafeArea → Column(min)
   ├─ ListTile(Icons.photo_camera, 'Kamera')  → pop(ImageSource.camera)
   └─ ListTile(Icons.photo_library, 'Galeri') → pop(ImageSource.gallery)
```

Setelah terpilih: `withoutAutoLock(ref, () => profilePhotoProvider.notifier.pick(source))` —
pembukaan kamera/galeri tidak memicu auto-lock. Pengambilan foto: `maxWidth: 800`, `imageQuality: 85`,
disimpan sebagai `profile_<millisSinceEpoch>.jpg` di direktori dokumen aplikasi.

#### `ProfileHeader` — `widgets/profile_header.dart`

```
Column
└─ ScrimImage(headerLaga, height: 230 × scale, scrim: 0.75,
              showPitchPattern: true, borderRadius: AppRadius.xl (28))
   └─ Padding(16) → ConstrainedBox(minHeight: tinggi − 32)
      └─ SingleChildScrollView → Column(end, start, min)
         ├─ [2] GestureDetector(onChoosePhoto) → Semantics('Ganti foto profil')
         │  └─ Stack(bottomRight)
         │     ├─ _ProfileAvatar(path)  → CircleAvatar(radius: 40, bg putih α 0.2)
         │     └─ CircleAvatar(radius: 16, Icon(Icons.edit, 16))
         ├─ SizedBox(12)
         ├─ [3] Baris nama — Flexible(Text(nama, headlineSmall, putih, w700, ≤2 baris))
         │        + SizedBox(4) + Padding(top 6) Icon(Icons.edit, 16, white70)
         ├─ SizedBox(4)
         ├─ Email (bodySmall, white70, 1 baris)
         ├─ SizedBox(12)
         └─ [4] Klub favorit — InkWell → Container(bg putih α 0.2, radius 20, border putih α 0.3)
                → Row(min): CircleAvatar(12)/ClubCrest(24) · 4 · Text · 4 · Icon(chevron_right, 20)
               [5] PillBadge(rank, accent)
```

**Metrik** · tinggi header `230 × scale` (→ maks 345) · scrim 0.75 · radius 28 · padding 16 ·
avatar `CircleAvatar(radius: 40)` → diameter 80 · badge edit `radius: 16` / ikon 16 ·
loading nama `148 × 26` · loading email `112 × 12` · crest klub 24 · chevron 20 · gap 12/4/8/6.

**Warna** · nama `Colors.white` · ikon edit `Colors.white70` · email `Colors.white70` ·
avatar & pil klub `Colors.white` α 0.2 · border pil `Colors.white` α 0.3 ·
ikon shield di placeholder `Colors.black87`.

**State**

| State | Tampilan |
|---|---|
| Nama sedang dimuat | `LinearProgressIndicator` di kotak `148 × 26` |
| Nama kosong | teks fallback "Profil saya" |
| Email sedang dimuat | `LinearProgressIndicator` di kotak `112 × 12` |
| Email kosong / error | `SizedBox.shrink()` (disembunyikan, tanpa pesan) |
| Tanpa foto | `CircleAvatar(radius: 40, bg putih α 0.2, child: Icon(Icons.person, 44, putih))` |
| Berkas hilang | sama dengan fallback ikon |
| Berkas ada | `CircleAvatar(radius: 40, backgroundImage: FileImage, child: null)` |

**Dialog ubah nama** — `AlertDialog` judul "Ubah nama", `TextField(maxLength: 30, autofocus)`,
pesan galat dari `validateDisplayName`: "Nama minimal 2 karakter" · "Nama maksimal 30 karakter" ·
"Nama tidak boleh mengandung karakter kontrol". Aksi "Simpan" aktif hanya bila galat `null`.
Berhasil → `SnackBar('Nama diperbarui')`.

#### `ProfileStats` & `ProfileSections` — `widgets/profile_sections.dart`

`ProfileStats` — `Row` 3 × `Expanded(StatTile)` dengan gutter 12:

| Tile | Ikon | Nilai | Keterangan |
|---|---|---|---|
| Stempel | `Icons.approval_outlined` | jumlah stamp | "PassportScreen" |
| Kartu | `Icons.style_outlined` | jumlah kartu | "N klub" |
| Pencapaian | `Icons.emoji_events_outlined` | jumlah achievement | "total" |

`ProfileSections` — `Column` dengan 6 `SettingsSection` dipisah `SizedBox(24)`:

| # | Section | Isi |
|---|---|---|
| 1 | **Aktivitas** | `SettingsTile` "Paspor Suporter" (ikon `Icons.verified` / `Icons.error`, subtitle "N stamp · N pencapaian · N catatan", chevron) · `SettingsTile` "Koleksi Kartu" (ikon `Icons.style_outlined`, chevron) |
| 2 | **Keamanan** | `SwitchListTile.adaptive` "Biometrik", ikon `Icons.fingerprint`, subtitle "Gunakan sidik jari saat membuka aplikasi" |
| 3 | **Notifikasi** | `SettingsTile` "Pengingat Kickoff", ikon `Icons.notifications_active_outlined`, subtitle "Mati" atau daftar lead time |
| 4 | **Data** | `SettingsTile` "Cadangan ke Cloud" (ikon `Icons.sync` atau spinner `24 × 24` sw2) + `TextButton('Cadangkan sekarang')` rata kanan |
| 5 | **Tentang** | `SettingsTile` "Kesan & Pesan", ikon `Icons.menu_book_outlined` → `FeedbackScreen` · catatan afiliasi (`bodySmall` + `fz.textMuted`) "Ultimate Fanzone tidak berafiliasi dengan Premier League…" |
| 6 | **Akun** | `SettingsTile` "Keluar" (`destructive: true`, ikon `Icons.logout`) → `confirmAndLogout` |

**Subtitle sinkronisasi** (`syncSubtitle`) — 5 status:
"Cloud belum dikonfigurasi" · "Mengirim data ke server…" · "Gagal: {error}" ·
"Otomatis saat ada internet." (+ "Terakhir: HH:MM") · ringkasan jumlah baris naik
(+ "Riwayat dipulihkan dari cloud" + catatan baris lokal yang tak bisa digabung).

---

### 4.2.5 Kesan & Pesan — `lib/features/dashboard/presentation/feedback_screen.dart` (72 baris)

Halaman statis tanpa provider, tanpa ikon, tanpa state.

**Struktur**

```
Scaffold + AppBar('Kesan & Pesan')                                  L19-20
└─ body: Center → ConstrainedBox(maxWidth: 720) → ListView          L21-24
   ├─ [1] Text('Mata Kuliah Pemrograman Aplikasi Mobile')           L27-32
   ├─ SizedBox(16)
   ├─ [2] AppCard → Column(start)
   │     Text('Kesan', titleSmall) · SizedBox(8) · Text(paragraph)  L35-46
   ├─ SizedBox(12)
   └─ [3] AppCard → Column(start)
         Text('Pesan', titleSmall) · SizedBox(8) · Text(paragraph)  L52-62
```

**Metrik** · padding `EdgeInsets.all(16)` (L25) · lebar 720 (L23) · jarak kartu 12 (L50) · jarak judul kartu 8.

**Tipografi** · judul utama `titleMedium` + `copyWith(fontWeight: w700)` · judul kartu `titleSmall` ·
paragraf **tanpa style** → mewarisi `bodyMedium` (Inter 14/w400).

**Warna** · semua teks `onSurface`; kartu `scheme.surface` dengan border `scheme.outline` 1 px, radius 20.

---
