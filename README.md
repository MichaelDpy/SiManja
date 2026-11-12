# SIMANJA — Sistem Informasi Manajemen Keuangan

Aplikasi manajemen keuangan pribadi berbasis Flutter dengan backend Firebase.

## Struktur Repositori

```
simanja/              ← root Git
├── lib/              ← source Dart (paket Flutter utama berada di root)
│   ├── core/         ← state, tema, model, utilitas keuangan
│   ├── screens/      ← halaman aplikasi
│   └── widgets/      ← widget bersama
├── assets/           ← aset statis (gambar, ikon)
├── android/          ← konfigurasi native Android
├── ios/              ← konfigurasi native iOS
├── test/             ← pengujian unit & widget
├── pubspec.yaml      ← dependensi Flutter
├── pubspec.lock      ← lockfile (di-commit, jangan diabaikan)
└── backend/          ← (belum ada) Firebase tools, rules, Cloud Functions
```

> **Catatan:** Kode Flutter berada langsung di root repositori ini (bukan di subdirektori `frontend/`). Folder `backend/` akan ditambahkan pada tahap integrasi Firebase.

## Memulai Pengembangan

```bash
# Pasang dependensi
flutter pub get

# Jalankan di emulator/perangkat
flutter run

# Analisis kode
flutter analyze

# Jalankan tes
flutter test
```

## Dependensi Utama

| Paket | Kegunaan |
|---|---|
| `fl_chart` | Grafik keuangan |
| `google_fonts` | Tipografi Lato |
| `intl` | Format tanggal & angka (lokal `id_ID`) |
| `flutter_svg` | Logo dan ikon SVG |
| `flutter_native_splash` | Splash screen native |
| `image_picker` | Foto profil lokal |

## Rencana Backend (Firebase)

Backend Firebase akan berada di folder `backend/` dan mencakup:
- Firebase Authentication (email/password)
- Cloud Firestore (transaksi & profil per pengguna)
- Security Rules dengan pengujian Emulator Suite

Lihat `00-panduan-tim.md` untuk pembagian tugas dan urutan integrasi lengkap.

## Kontribusi

Ikuti aturan commit di `00-panduan-tim.md`. Jalankan `flutter analyze` sebelum membuat commit.
