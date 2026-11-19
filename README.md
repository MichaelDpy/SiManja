# SIMANJA — Sistem Informasi Manajemen Keuangan

Aplikasi manajemen keuangan pribadi berbasis Flutter dengan Firebase Auth dan Cloud Firestore. Milestone ini mencakup autentikasi, profil/preferensi, dan CRUD transaksi per pengguna. Target awal “backend sekitar 50%” adalah batas fitur, bukan persentase kode atau klaim siap produksi.

Default pengembangan memakai **Firebase Emulator dengan project `demo-simanja`**. Project cloud asli belum dikonfigurasi, diuji, atau di-deploy.

| Folder | Isi |
| --- | --- |
| `frontend/` | Aplikasi Flutter, aset, konfigurasi platform, dan pengujian |
| `backend/` | Konfigurasi Firebase Emulator, indeks Firestore, dan security rules |

Alur data: `Auth → UID → repository → AppState/ChangeNotifier → UI`. Bootstrap ada di `frontend/lib/core/firebase_bootstrap.dart`, repository di `frontend/lib/repositories/`, dan pengujian emulator di `backend/test/`.

## Menjalankan pengembangan

Lingkungan verifikasi: Flutter 3.47.2/Dart 3.13.2, Node.js 22.20.0, JDK 25.0.2. Tooling backend mensyaratkan Node.js minimal 22.16.0. Perintah berikut memakai PowerShell dari root repository.

Terminal pertama:

```powershell
cd backend
npm.cmd ci
npm.cmd run emulators
```

Terminal kedua:

```powershell
cd frontend
flutter pub get
flutter run --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_PROJECT_ID=demo-simanja
```

Auth memakai port `9099`, Firestore `8080`, dan UI emulator `http://127.0.0.1:4000`. Konfigurasi server ada di `backend/firebase.json`. Host aplikasi ditentukan oleh target:

| Target | Host aplikasi |
| --- | --- |
| Android Emulator standar | Default `10.0.2.2` |
| iOS Simulator, desktop, atau browser pada komputer yang sama | Default `127.0.0.1` |
| Perangkat fisik | IP LAN komputer, melalui `--dart-define=FIREBASE_EMULATOR_HOST=IP_KOMPUTER` |

Perangkat fisik perlu berada pada jaringan yang sama dan dapat mengakses port emulator komputer. Bila mengubah port server, samakan `FIREBASE_AUTH_PORT` dan `FIREBASE_FIRESTORE_PORT` pada `--dart-define`. Akses HTTP emulator Android disiapkan pada konfigurasi **debug**. Target selain Android belum diverifikasi secara manual. Rujukan koneksi: [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite/connect_and_prototype).

Buat akun demo melalui tombol daftar pada aplikasi atau melalui UI Auth Emulator. Transaksi akun baru memang kosong. Tidak ada seed otomatis dari `MockData`; data contoh hanya boleh ditambahkan secara eksplisit pada emulator. Reset password di emulator menghasilkan tautan lokal, bukan email sungguhan.

Data server emulator secara default hilang ketika emulator dihentikan. Untuk menyimpan sesi demo, jalankan `npx.cmd firebase emulators:export .cache/demo-data --project demo-simanja` dari `backend/` saat emulator masih berjalan. Pada start berikutnya gunakan:

```powershell
# Dari backend/, setelah hasil export tersedia.
npx.cmd firebase emulators:start --project demo-simanja --import=.cache/demo-data --export-on-exit=.cache/demo-data
```

Folder `.cache/` tidak ikut Git. Jangan memakai perintah pengujian untuk menyimpan data demo; tes membersihkan data emulator pengujiannya.

## Menghubungkan project Firebase asli

Pilih project yang benar di Firebase Console, daftarkan aplikasi sesuai target, aktifkan provider **Email/Password** di Authentication, dan siapkan database Cloud Firestore `(default)`. Android saat ini memakai application ID `com.example.simanja`; registrasi target harus sesuai konfigurasi aplikasi. Ikuti [setup Flutter](https://firebase.google.com/docs/flutter/setup) dan [Auth email/password](https://firebase.google.com/docs/auth/flutter/password-auth).

Bootstrap repository ini membaca `FirebaseOptions` melalui Dart defines. Isi `frontend/config/firebase.local.json` dengan nilai asli dari konfigurasi aplikasi Firebase target; file tersebut diabaikan Git. Contoh struktur berikut adalah placeholder, bukan konfigurasi project yang dapat dipakai:

```json
{
  "USE_FIREBASE_EMULATORS": false,
  "FIREBASE_PROJECT_ID": "ISI_PROJECT_ID_ASLI",
  "FIREBASE_API_KEY": "ISI_API_KEY_APLIKASI",
  "FIREBASE_APP_ID": "ISI_APP_ID_TARGET",
  "FIREBASE_MESSAGING_SENDER_ID": "ISI_SENDER_ID"
}
```

Tambahkan `FIREBASE_AUTH_DOMAIN` untuk target Web dan `FIREBASE_IOS_BUNDLE_ID` untuk target iOS sesuai konfigurasi aslinya. App ID berbeda untuk setiap target; pilih konfigurasi yang sesuai saat menjalankan:

```powershell
# Dari frontend/, setelah konfigurasi asli diisi.
flutter run --dart-define-from-file=config/firebase.local.json
```

Konfigurasi client tidak memerlukan service-account/private key. Password dikelola Firebase Auth dan tidak disimpan pada dokumen Firestore. Jangan memasukkan token CLI atau private credential ke repository.

Rules lokal tidak otomatis berlaku di cloud. Setelah pengguna benar-benar memilih project tujuan, deploy rules dilakukan dari `backend/` menggunakan `npx.cmd firebase deploy --only firestore:rules --project ID_PROJECT_YANG_DIPILIH`. Ganti placeholder dengan ID yang telah diperiksa; perintah ini **belum dijalankan** pada pekerjaan ini. Rujukan: [deploy Firebase Security Rules](https://firebase.google.com/docs/rules/manage-deploy).

## Schema dan perilaku penyimpanan

| Lokasi | Field |
| --- | --- |
| `users/{uid}` | `name`, `phone`, `address`, `city`, `job` berupa string; `monthlyIncome` integer nonnegatif; `darkMode`, `notifEnabled` boolean; `createdAt`, `updatedAt` server Timestamp |
| `users/{uid}/transactions/{id}` | `category`, `description` string; `amount` integer positif; `isIncome` boolean; `date` Timestamp; `createdAt`, `updatedAt` server Timestamp |

Nominal maksimal `9007199254740991` rupiah agar konversi ke model `double` tetap tepat. ID transaksi berasal dari document ID acak Firestore; create memeriksa benturan dan edit mempertahankan ID serta `createdAt`. Tanggal disimpan sebagai instant tengah malam kalender lokal; tampilan tanggal dapat berbeda bila zona waktu perangkat berubah.

Profil dibuat idempoten ketika dokumen belum ada. Penyimpanan berikutnya hanya mengirim field yang berubah. Email identitas berasal dari Auth dan read-only pada Profil. Rules membatasi akses sesuai UID, memvalidasi schema/tipe/batas, dan menolak path lain. Penghapusan profil/akun belum disediakan.

Satu stream transaksi aktif mengisi Dasbor, Transaksi, Data, dan Analitik. Logout/pergantian UID membatalkan stream, membersihkan data, dan mengabaikan callback sesi lama. Tidak ada fallback transaksi dummy saat error. UI membedakan loading, kosong, cache, write tertunda, dan error/retry; sukses mutasi menunggu konfirmasi repository. Bootstrap profil dan create transaksi melalui transaction membutuhkan koneksi server. Cache mengikuti SDK/platform; belum ada antrean offline khusus. Profil dimuat saat membuka sesi/retry, belum realtime antarperangkat.

Foto masih lokal pada sesi/perangkat dan dikosongkan saat logout/pergantian akun; belum Firebase Storage. Aset/rekening tetap berlabel data contoh dan tidak berubah akibat CRUD transaksi. Analitik serta CSV dihitung di perangkat; ringkasan notifikasi bukan push notification. Backlog berikutnya: aset/rekening cloud dan mutasi saldo, anggaran/target tabungan, Storage, FCM, Cloud Functions, serta penghapusan akun menyeluruh.

## Verifikasi dan handoff

Jalankan tes backend saat emulator pengembangan sudah dihentikan agar port tidak bertabrakan:

```powershell
# Dari backend/: menyalakan Auth/Firestore Emulator, menjalankan tes, lalu menghentikannya.
npm.cmd test
```

Tes memakai project demo dan endpoint lokal. Pengujian rules menggunakan client pemilik, akun lain, serta tanpa sesi; integrasi Auth memeriksa login ulang, reset password hingga kredensial baru, persistensi, dan listener antarclient.

Hasil yang benar-benar dijalankan pada 19 November 2026:

| Pemeriksaan | Hasil |
| --- | --- |
| `flutter analyze --no-pub` dari `frontend/` | Bersih |
| `flutter test --no-pub` dari `frontend/` | Seluruh 167 tes lulus |
| `npm.cmd test` dari `backend/` | Seluruh 66 tes emulator lulus |
| APK debug Android | Berhasil dibangun dengan opsi Kotlin sementara di bawah |
| Runtime pada perangkat fisik/iOS dan project cloud asli | Belum diuji; tidak ada deploy cloud |

Uji widget gabungan memakai repository/Auth pengujian untuk menjalankan login → tambah/edit transaksi → tabel/grafik → simpan profil → logout → akun B kosong → login ulang A → hapus. Uji emulator terpisah membuktikan perilaku Auth/Firestore nyata. Dua tes aset lama disesuaikan dengan dataset saat ini (enam kategori, total Rp 87.000.000) dan navigasi chip yang dapat digeser, tanpa mengubah fitur aset.

Pada verifikasi C8, build awal gagal pada cache incremental Kotlin Windows dan berhasil dengan opsi sementara. Perbaikan tanggal 20 November 2026 menyimpan `kotlin.incremental=false` dan `kotlin.compiler.execution.strategy=in-process` pada `frontend/android/gradle.properties`, sehingga build standar berikut sudah berhasil tanpa flag tambahan:

```powershell
# Dari frontend/.
flutter build apk --debug --no-pub
```

APK ada di `frontend/build/app/outputs/apk/debug/app-debug.apk` dan tidak ikut Git. Pada pemeriksaan 20 November 2026, startup dari proses baru juga berhasil menampilkan halaman awal di Android Emulator Pixel 7a. Perangkat fisik/iOS belum diverifikasi.

Untuk demo/handoff A8: daftar akun A, tambah pemasukan/pengeluaran pada periode yang dipilih, tunjukkan perubahan Dasbor/Data/Analitik, lalu edit/hapus. Simpan nama/tema dan login ulang untuk menunjukkan persistensi. Buka akun B untuk menunjukkan data terpisah, kemudian tunjukkan cache/pending/error tanpa menyebut write tertunda sudah diterima server.

Jawaban presentasi mengikuti batas implementasi: aset tidak ikut berubah karena masih data contoh; pemisahan akun ditegakkan oleh rules selain UI; password dikelola Auth; verifikasi backend saat ini menggunakan emulator.
