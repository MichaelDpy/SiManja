# SIMANJA — Sistem Informasi Manajemen Keuangan

Aplikasi manajemen keuangan pribadi berbasis Flutter dengan Firebase Auth dan Cloud Firestore. Milestone ini mencakup autentikasi, profil/preferensi, dan CRUD transaksi per pengguna. Target awal “backend sekitar 50%” adalah batas fitur, bukan persentase kode atau klaim siap produksi.

Default pengembangan memakai **Firebase Emulator dengan project `demo-simanja`**. Project cloud asli belum dikonfigurasi, diuji, atau di-deploy.

| Folder | Isi |
| --- | --- |
| `frontend/` | Aplikasi Flutter, aset, konfigurasi platform, dan pengujian |
| `backend/` | Konfigurasi Firebase Emulator, indeks Firestore, dan security rules |
| `docs/` | Panduan presentasi: skenario demo, alur Firebase, status fitur, kontribusi, dan backlog (`docs/presentasi.md`) |

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

Pilih project yang benar di Firebase Console, daftarkan aplikasi sesuai target, aktifkan provider **Email/Password** di Authentication, dan siapkan database Cloud Firestore `(default)`. Android memakai application ID **`com.simanja.app`** (keputusan tim 26 November 2026), jadi daftarkan aplikasi Android Firebase dengan ID tersebut. Bundle ID iOS masih `com.example.simanja` karena target iOS belum diputuskan. Ikuti [setup Flutter](https://firebase.google.com/docs/flutter/setup) dan [Auth email/password](https://firebase.google.com/docs/auth/flutter/password-auth).

### Lingkungan Firebase (dev / staging / production)

Satu-satunya sumber konfigurasi adalah Dart define yang dibaca `frontend/lib/core/firebase_environment.dart`. Nilai itu divalidasi sebelum `FirebaseBootstrap` memanggil `Firebase.initializeApp`, dan hanya ada satu app Firebase default.

| `SIMANJA_ENV` | Backend | Aturan |
| --- | --- | --- |
| `dev` (default bila tidak diisi) | Firebase Emulator, project `demo-*` | Ditolak pada build rilis. `FIREBASE_EMULATOR_HOST` opsional, berupa IP/host tanpa skema atau port. |
| `staging` | Project cloud non-produksi | Wajib `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID` dengan format Firebase yang sah. |
| `production` | Project cloud rilis | Aturannya sama dengan staging. Hanya aktif bila dipilih eksplisit, tidak pernah dipilih otomatis. |

Untuk staging/production, nilai berikut ditolak: project `demo-*`, placeholder `ISI_…`, App ID platform lain (misalnya App ID web pada build Android), App ID yang sender-nya tidak cocok, dan `FIREBASE_EMULATOR_HOST`. Target Web/desktop juga wajib `FIREBASE_AUTH_DOMAIN`, dan iOS wajib `FIREBASE_IOS_BUNDLE_ID`. Flag lama `USE_FIREBASE_EMULATORS` masih diterima: `true` berarti dev, `false` berarti staging. Flag itu ditolak bila bertentangan dengan `SIMANJA_ENV`.

Konfigurasi yang tidak valid menampilkan halaman "Konfigurasi Firebase tidak valid" beserta nama field yang bermasalah, tanpa menampilkan nilainya dan tanpa tombol coba lagi, karena aplikasi harus di-build ulang. Kegagalan runtime (jaringan atau emulator mati) menampilkan tombol "Coba lagi". Tidak ada fallback ke emulator atau data dummy.

Salin contoh di `frontend/config/` menjadi `firebase.<env>.json` lalu isi dengan nilai asli dari Firebase Console. File `firebase.*.json` diabaikan Git, kecuali `*.example.json` yang berisi placeholder:

```powershell
# Dari frontend/.
Copy-Item config/firebase.staging.example.json config/firebase.staging.json
```

```powershell
flutter run --dart-define-from-file=config/firebase.staging.json
```

**Login Google (opsional).** Aktifkan provider Google di Firebase Console → Authentication. Untuk Android, isi `GOOGLE_SERVER_CLIENT_ID` dengan *Web client ID* OAuth project (`…apps.googleusercontent.com`, bukan secret), lalu daftarkan fingerprint SHA-1/SHA-256 setiap kunci yang dipakai: debug tiap laptop, upload, dan Play App Signing. Kalau nilainya kosong, tombol Google tidak ditampilkan di Android. Di Web, login Google memakai popup Firebase, termasuk popup tiruan dari Auth Emulator.

Dengan setelan default Firebase "satu akun per email" (terbukti di Auth Emulator):
- Login Google memakai email akun password yang **belum terverifikasi**: UID tetap sama, tetapi Firebase mencabut password-nya.
- Bila email itu **sudah terverifikasi**, kedua metode tetap aktif.
- Aplikasi tidak pernah menggabungkan dua UID. Google milik akun lain ditolak.
- Melepas metode masuk terakhir dicegah di aplikasi, karena server Firebase sendiri mengizinkannya.

App ID berbeda untuk setiap platform, jadi siapkan file per target bila perlu. Konfigurasi client ini bukan secret server, tetapi setiap anggota mengisi target miliknya sendiri. Nilai staging/production asli belum tersedia, sehingga inisialisasi ke project cloud **belum diverifikasi**.

### Signing rilis Android

Build debug/profile memakai kunci debug lokal Android SDK. Build rilis (`flutter build apk --release` / `appbundle`) **hanya** memakai kunci rilis dari `frontend/android/key.properties`. Tanpa file itu, build rilis berhenti dengan pesan "memerlukan kunci rilis" dan tidak pernah memakai kunci debug.

Pemilik rilis membuat keystore di luar repository, lalu menulis `frontend/android/key.properties`:

```properties
storeFile=C:/lokasi/aman/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`key.properties`, `*.jks`, `*.keystore`, dan `*.p12` diabaikan Git. Jangan mengirim keystore atau password lewat chat, PR, atau file bersama. Fingerprint SHA-1/SHA-256 sertifikat (bukan rahasia) didaftarkan ke Firebase/Google untuk login Google: kunci debug setiap laptop berbeda, sedangkan fingerprint kunci rilis dan Play App Signing dicatat saat kunci tersebut tersedia.

Konfigurasi client tidak memerlukan service-account/private key. Password dikelola Firebase Auth dan tidak disimpan pada dokumen Firestore. Jangan memasukkan token CLI atau private credential ke repository.

Rules lokal tidak otomatis berlaku di cloud. Setelah pengguna benar-benar memilih project tujuan, deploy rules dilakukan dari `backend/` menggunakan `npx.cmd firebase deploy --only firestore:rules --project ID_PROJECT_YANG_DIPILIH`. Ganti placeholder dengan ID yang telah diperiksa; perintah ini **belum dijalankan** pada pekerjaan ini. Rujukan: [deploy Firebase Security Rules](https://firebase.google.com/docs/rules/manage-deploy).

## Permintaan hapus akun (Cloud Functions, B10)

Layanan tepercaya berada di `backend/functions/`: Node 22, `firebase-functions` v2, region `us-central1` sampai region R00 diputuskan. Layanan ini **hanya diuji di Firebase Emulator**. Deploy membutuhkan paket Blaze serta keputusan target dan region, jadi belum dilakukan.

| Callable | Perilaku |
| --- | --- |
| `getAccountDeletionStatus` | Status milik pemanggil: `none` / `requested` / `processing` / `completed` / `failed` / `cancelled` |
| `requestAccountDeletion({requestId})` | Wajib login dengan `auth_time` ≤ 5 menit dan akun Auth aktif. Membuat `requested` sekali saja; permintaan ulang mengembalikan status yang ada (idempoten, berbasis transaction). |
| `cancelAccountDeletion()` | Hanya saat `requested`. Tanpa permintaan, status tidak berubah. `processing`/`completed` ditolak. |

UID selalu diambil dari token Auth. Field `uid` di payload diabaikan. Status disimpan di `accountLifecycle/{uid}`, koleksi khusus Admin SDK: rules client default-deny sehingga aplikasi tidak bisa membaca atau mengubahnya. Kontrak lanjutan (pembekuan write C09, worker pembersihan B11, revokasi dan retensi B12, UI B13) memakai status `requested`/`processing`/`completed` sebagai sinyal beku. Client Dart ada di `frontend/lib/services/account_deletion_service.dart`.

Emulator Functions berjalan di port `5001` dan ikut menyala lewat `npm.cmd run emulators`. Script itu juga memasang dependensi `functions/` lebih dulu. Untuk perangkat fisik, port 5001 juga harus dapat dijangkau, sama seperti 9099 dan 8080.

### Kontrak R-DELETE (B2-07, masukan C09)

Sumber kode: `backend/functions/src/deletion.js` (produsen), `frontend/lib/services/account_deletion_service.dart` (konsumen). Rules C09 menegakkan pembekuan.

| Status | Arti | Write normal pengguna | Dapat dibatalkan |
| --- | --- | --- | --- |
| `none` (dokumen tidak ada) | Tidak ada permintaan | Dibuka | — |
| `requested` | Diterima, menunggu worker (B11) | **Beku** | Ya |
| `processing` | Worker menghapus data | **Beku** | Tidak |
| `failed` | Worker gagal; data mungkin sudah terhapus sebagian | **Beku** | Tidak (ulang dengan `requestId` baru → `requested`) |
| `completed` | Selesai | **Beku** (tombstone) | Tidak |
| `cancelled` | Dibatalkan sebelum ada data yang dihapus | Dibuka | — |

- **Transisi sah:** `none|cancelled|failed → requested` (callable), `requested → cancelled` (callable), `requested → processing → completed|failed` (worker B11, Admin SDK, transaction + `version`).
- **Dokumen:** `accountLifecycle/{uid}`, berisi `state`, `requestId`, `requestedAtMs`, `updatedAtMs`, `version`, `previousState`, dan opsional `cancelledAtMs`. Tanpa email/PII. Hanya Admin SDK yang boleh membaca dan menulis; client tidak punya akses baca maupun tulis.
- **Pembekuan untuk C09:** tolak create/update/delete pada `users/{uid}` dan `users/{uid}/transactions/{id}` bila dokumen `accountLifecycle/{uid}` ada dengan `state` ∈ {`requested`, `processing`, `failed`, `completed`}. `none` (dokumen tidak ada) dan `cancelled` membuka write. Uji replay token lama dan pending write setelah `completed` dimiliki B2-12 bersama C09.
- **Otorisasi:** UID hanya dari token, `auth_time` ≤ 300 detik untuk permintaan, akun Auth aktif. `requestId` = kunci idempotensi (permintaan ulang tidak membuat job kedua). Error memakai `HttpsError` dengan `details.reason`: `unauthenticated`, `requires-recent-login`, `invalid-request-id`, `account-disabled`, `account-not-found`, `deletion-not-cancellable`.
- **Status setelah Auth dihapus:** pemilik tidak bisa lagi memanggil callable (tidak ada token). Tidak ada pencarian status publik berbasis UID. Bukti minimum bagi pengguna adalah `requestId` yang ditampilkan saat permintaan diterima. Jalur pengecekan status setelah akun hilang (bila diperlukan) dirancang di B2-16 dengan verifikasi identitas, bukan membuka `accountLifecycle`.
- **Retensi tombstone:** dokumen `completed` dipertahankan sebagai pengaman anti-rekreasi. **Durasinya belum diputuskan (OPEN, pemilik data/C12)**, jadi B2-12 terblokir pada keputusan ini, bukan TTL tebakan.
- **Region/target:** `us-central1` sementara sampai region R00 diputuskan; client dan server memakai konstanta yang sama. Hanya diuji di emulator; deploy membutuhkan Blaze dan target project.

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

### Pemeriksaan integrasi akhir (A8, 26 November 2026)

| Pemeriksaan | Hasil |
| --- | --- |
| `flutter analyze --no-pub` dari `frontend/` | Bersih |
| `flutter test --no-pub` dari `frontend/` | Seluruh 187 tes lulus, termasuk `test/layout_audit_test.dart` (enam tab pada 320/360/412/landscape × teks 1,0/1,5 × terang/gelap, rotasi, periode Dasbor) |
| `npm.cmd test` dari `backend/` | Seluruh 66 tes emulator lulus |
| `flutter build apk --debug --no-pub` dari `frontend/` | Berhasil (`build/app/outputs/flutter-apk/app-debug.apk`) |
| Uji manual alur lengkap (daftar/login → CRUD → Data/Dasbor/Analitik → profil → buka ulang → logout → akun kedua) | **Belum dijalankan pada A8.** Akan diuji manual di HP Android oleh tim; alur yang sama sudah tercakup tes widget dan tes emulator di atas |
| iOS, project Firebase asli | Belum diuji |

A8 memperbaiki overflow pada layar sempit/teks besar (Dasbor, Aset, Transaksi, Profil), state tab yang hilang saat rotasi, filter periode Dasbor yang tertinggal setelah CRUD, dan avatar Dasbor tanpa fallback saat file foto lokal hilang.

Skenario demo, status fitur cloud/lokal/contoh, pembagian kontribusi, cara menjawab batas fitur, dan backlog tahap 2 ada di [`docs/presentasi.md`](docs/presentasi.md).
