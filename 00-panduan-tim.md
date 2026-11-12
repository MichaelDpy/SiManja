# Rencana polishing SIMANJA dan backend Firebase tahap 1

Dokumen ini adalah rencana dan kumpulan prompt. Belum ada implementasi aplikasi yang dilakukan dalam penyusunannya.

## Pembagian: 8 commit per orang, total 24 commit

Delapan commit dipilih agar tiap commit menghasilkan perubahan yang bisa diperiksa dan dicoba. Beban dinilai dari cakupan pekerjaan, bukan jumlah file atau baris. Satu prompt dijalankan sampai tuntas sebelum prompt berikutnya milik orang yang sama.

| Penanggung jawab | Fokus | Dokumen prompt |
| --- | --- | --- |
| Anggota 1 — kamu | Fondasi frontend, tema bersama, state, navigasi, dasbor, aset, integrasi akhir | `01-anggota-1.md` |
| Anggota 2 | Form transaksi, tabel, ekspor CSV, analitik, profil dan foto lokal | `02-anggota-2.md` |
| Anggota 3 | Firebase, autentikasi, sesi, profil cloud, transaksi cloud, rules dan pengujian emulator | `03-anggota-3.md` |

## Arti target backend sekitar 50%

Ini batas milestone proyek, bukan pengukuran persentase kode atau jaminan kesiapan produksi. Pada tahap ini alur inti harus benar-benar berjalan:

- Firebase Core, Authentication email/password, dan Cloud Firestore terhubung, minimal melalui Emulator Suite yang terdokumentasi.
- Login, pendaftaran sederhana, pemulihan password, sesi, serta logout berjalan melalui Firebase Auth.
- Profil teks dan preferensi pengguna tersimpan pada dokumen milik UID pengguna.
- Transaksi mendukung baca/tambah/edit/hapus melalui Firestore. Dasbor, Data, dan Analitik membaca state transaksi yang sama.
- Rules membatasi akses per pengguna dan memvalidasi data; pengujian dua akun membuktikan isolasi.

Yang dicicil pada tahap berikutnya: rekening dan aset cloud beserta mutasi saldo, anggaran/target tabungan, Firebase Storage untuk foto, push notification/FCM, analitik server/Cloud Functions, ekspor cloud, penghapusan akun menyeluruh, dan penyempurnaan produksi. Analitik transaksi tahap ini dihitung di perangkat. CSV tahap ini juga dibuat di perangkat. Foto profil masih lokal dan dijelaskan sebagai lokal.

Jika Firebase project asli belum diberikan, gunakan emulator dengan ID demo yang valid. Jangan mengklaim koneksi cloud sudah diuji. Catat mana yang diuji di emulator dan mana yang belum diuji di project asli.

## Temuan yang menjadi dasar pekerjaan

- Kode Flutter berada di `frontend/`; belum ada backend. Git masih mencatat file lama di root sebagai terhapus dan `frontend/` sebagai belum terlacak.
- `AppState` dan Login merujuk `MockData.dummyUser`, tetapi definisinya tidak ditemukan dalam source saat pemeriksaan. Ini calon penghambat kompilasi yang harus diselesaikan pada A3, bukan sekadar dipoles tampilannya.
- Tema terang sudah didefinisikan, tetapi banyak warna gelap masih ditulis langsung pada halaman/widget.
- Tabel Data dan Analitik memakai sumber dummy berbeda dari transaksi yang dapat diedit.
- Persentase aset dummy jika dijumlahkan mencapai 102%; nilai persentase perlu dihitung dari nilai aset. Label “aset bersih” belum didukung data kewajiban.
- Rasio tabungan, bulan/periode, pertumbuhan aset, dan sebagian pesan notifikasi masih berupa angka/teks tetap.
- Tombol filter aset dan unduh data belum memiliki aksi.
- Splash menuju Login, sementara Intro terdaftar tetapi tidak dilewati alur awal. Intro juga dapat langsung menuju Home.
- Foto memakai `dart:io`/`FileImage`, izin iOS belum menyertakan penjelasan kamera/galeri, dan penanganan kegagalan pemilihan foto belum lengkap.
- State belum persisten; beberapa operasi async belum aman saat halaman sudah ditutup. Tes saat ini hanya smoke test.

## Aturan umum untuk semua prompt

Tempelkan aturan ini sekali di awal sesi kerja setiap anggota, lalu jalankan prompt commit satu per satu:

```text
Kamu bekerja pada repository SIMANJA. Root Git berada di folder simanja, package Flutter berada di frontend/. Baca AGENTS.md jika tersedia, periksa git status dan kode terbaru sebelum mengubah apa pun. Kerjakan hanya satu prompt commit yang sedang diberikan. Pertahankan perubahan pengguna yang sudah ada. Jangan reset/clean, force push, atau memasukkan perubahan anggota lain ke commit.

Gunakan arsitektur yang sudah ada: Flutter Material, AppState/ChangeNotifier, intl, fl_chart, dan widget bersama. Jangan mengganti framework atau melakukan rewrite besar. Semua teks pengguna berbahasa Indonesia. Nominal memakai rupiah tanpa desimal dan tanggal ditampilkan secara konsisten. Jangan menampilkan angka fiktif sebagai hasil perhitungan nyata.

Perbaiki layout pada area prompt secara menyeluruh: tema terang/gelap, lebar 320/360/412 logical pixels, landscape, skala teks sampai 1,5, teks panjang, keyboard, safe area, empty/loading/error state. Gunakan Expanded/Flexible/Wrap/LayoutBuilder sesuai kebutuhan; jangan menyembunyikan overflow dengan mengecilkan semua teks. Pertahankan enam menu dan identitas teal SIMANJA.

Lakukan format pada file yang diubah. Jalankan flutter analyze dan pengujian yang relevan dari frontend/ jika lingkungan siap. Tambahkan tes untuk logika bisnis, sinkronisasi, autentikasi/rules, dan regresi yang bermakna; perubahan kosmetik cukup diverifikasi visual. Jangan mengaku tes berhasil jika belum dijalankan. Laporkan hambatan lingkungan dengan tepat.

Setelah perubahan dan pemeriksaan selesai, tinjau diff lalu buat tepat satu commit lokal dengan pesan yang diberikan. Stage file/hunk milik pekerjaan ini saja. Jangan push atau merge otomatis. Laporkan file berubah, perilaku yang diperbaiki, hasil pemeriksaan, hash commit, dan keterbatasan yang masih ada. Bila prasyarat anggota lain belum masuk, jelaskan dependensinya; jangan membuat implementasi pengganti yang nantinya bentrok.
```

## Kontrak antarmodul

Anggota 1 menetapkan kontrak ini pada A3; anggota lain menggunakannya, dan Anggota 3 mempertahankannya ketika memasang Firestore.

- `AppState.instance` tetap menjadi facade UI. Sumber transaksi hanya `AppState.transactions`, berupa daftar yang tidak dapat diubah langsung oleh widget.
- Pisahkan `TransactionModel` dari data dummy ke `lib/models/transaction_model.dart`. `mock_data.dart` boleh melakukan re-export untuk menjaga kompatibilitas import lama. Jangan serialisasikan `IconData`/`Color`; petakan kategori ke ikon/warna di lapisan presentasi bersama.
- Pertahankan field yang sudah dipakai UI: `id`, `category`, `description`, `amount`, `isIncome`, `date`. `amount` domain tetap `double` agar kompatibel, tetapi wajib finite, positif, dan rupiah bulat. Firestore menyimpan integer rupiah; konversi hanya setelah validasi. Jangan menerima NaN, Infinity, atau pecahan.
- Tetapkan `Future<void> addTransaction(TransactionModel tx)`, `Future<void> updateTransaction(String id, TransactionModel tx)`, `Future<void> deleteTransaction(String id)`. Edit memakai ID stabil, bukan indeks daftar tersaring. `generateId()` tetap tersedia dan ID tidak berubah saat edit. Tahap cloud memeriksa benturan ID; jangan hanya mengandalkan timestamp milidetik.
- Sediakan `transactionsLoading`, `transactionsError`, dan `Future<void> retryTransactions()` pada AppState. Saat mutasi gagal, Future gagal dengan pesan yang bisa dipetakan ke UI; jangan menelan error atau menampilkan sukses palsu. Implementasi lokal A3 langsung selesai dan menyediakan state yang sama.
- Utility laporan menyediakan `filterTransactions`, `totalIncome`, `totalExpense`, `netCashFlow`, `monthlySeries`, `expenseByCategory`, dan `savingsRate` melalui `lib/core/finance_summary.dart`. UI tidak mengulang rumus sendiri. Batas bulan memakai awal bulan inklusif dan awal bulan berikutnya eksklusif. Rasio tabungan = (pemasukan - pengeluaran) / pemasukan x 100%; tampilkan “—” saat pemasukan nol, dan nilai negatif tetap sah.
- Transaksi awal diurutkan tanggal terbaru lalu ID sebagai pembanding stabil. Periode laporan punya label tahun dan bulan; rentang enam bulan mencakup bulan tanpa transaksi dengan nilai nol. Jangan menganggap bulan kalender sekarang selalu berisi data.
- Aset/rekening tetap data demo terpisah pada tahap ini. Beri label “Data contoh”; jangan mengklaim CRUD transaksi otomatis memutasi saldo rekening atau nilai investasi.
- Root Firebase tooling berada di `backend/`: `firebase.json`, `firestore.rules`, konfigurasi indeks bila perlu, dan tes rules. Schema: `users/{uid}` untuk profil/preferensi; `users/{uid}/transactions/{transactionId}` untuk transaksi. Field transaksi cloud: `category`, `description`, `amount` integer positif, `isIncome` boolean, `date` Timestamp, `createdAt` dan `updatedAt` server Timestamp. ID berasal dari document ID. Update mempertahankan `createdAt`.
- Profil cloud menyimpan nama, telepon, alamat, kota, pekerjaan, pendapatan bulanan, serta preferensi tema/ringkasan. Email identitas berasal dari Firebase Auth dan tampil read-only di profil sampai fitur perubahan email terverifikasi dibuat. Jangan menyimpan password atau path foto lokal di Firestore.
- Tidak ada fallback dummy diam-diam saat cloud error. Data transaksi akun baru kosong. Seed hanya tindakan eksplisit di emulator, dengan penanda demo. Saat logout/pergantian UID, hentikan stream dan kosongkan data pengguna sebelumnya.

## Urutan integrasi agar minim konflik

1. A1 menyiapkan struktur Git; semua anggota mulai dari baseline yang sama.
2. A2 menyiapkan tema/widget bersama. A3 menetapkan model, kontrak AppState, utility keuangan, dan fixture demo. B mulai dari hasil A2+A3. C dapat menyiapkan tooling C1 setelah A1; integrasi startup dan commit C1 menunggu A4. C2 dimulai setelah C1 selesai.
3. A4 menyelesaikan alur intro/login; C3 baru mengubah main/splash/routing setelah A4. A5-A7 dan B1-B8 dapat berjalan pada file masing-masing.
4. C4 baru menyentuh halaman Profil setelah B8 terintegrasi. C5 membutuhkan kontrak A3. C6 memasang Firestore ke AppState setelah C3-C5 dan B1-B3 terintegrasi.
5. C7 menyelesaikan rules dan tes; C8 mendokumentasikan serta memverifikasi backend. A8 menjadi pemeriksaan integrasi terakhir setelah seluruh pekerjaan B dan C masuk.

Kepemilikan file bersama: `theme.dart`/widget bersama oleh A2; `AppState` dan model oleh A3 lalu C4/C6 secara berurutan; `main.dart`/splash oleh A4 lalu C1/C3; profil oleh B8 lalu C4; `pubspec.yaml`/lockfile dikoordinasikan B4, B8, dan C1 secara berurutan. Sinkronkan perubahan package sebelum menjalankan resolusi dependensi berikutnya. Konflik pada file bersama harus ditinjau, bukan dipilih seluruhnya dengan ours/theirs.

## Kriteria akhir untuk presentasi

- Demonstrasi transaksi baru langsung mengubah Dasbor, Data, dan Analitik; edit/hapus juga konsisten dan data bertahan setelah login ulang pada backend yang sedang digunakan.
- Akun A dan B tidak saling melihat data. Logout menutup sesi, membersihkan data, dan tombol Back tidak membuka halaman terlindungi.
- Tidak ada tombol aktif tanpa hasil; tidak ada label persen/periode/notifikasi palsu. Kondisi data kosong dan jaringan gagal punya penjelasan serta tindakan yang sesuai.
- Tema terang/gelap, nominal besar, nama panjang, keyboard, layar sempit, dan pembesaran teks tetap dapat digunakan.
- Dokumentasi membedakan fitur cloud nyata, fitur lokal, data contoh, hasil tes yang benar-benar dijalankan, dan pekerjaan tahap berikutnya.

## Referensi Firebase

- Setup dan FlutterFire: https://firebase.google.com/docs/flutter/setup
- Authentication Flutter: https://firebase.google.com/docs/auth/flutter/start
- Firestore Flutter: https://firebase.google.com/docs/firestore/quickstart?platform=flutter
- Rules dan pengujian emulator: https://firebase.google.com/docs/firestore/security/test-rules-emulator
- Emulator Suite: https://firebase.google.com/docs/emulator-suite/install_and_configure