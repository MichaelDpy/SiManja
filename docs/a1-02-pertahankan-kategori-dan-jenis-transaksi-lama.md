# A1-02 — Pertahankan kategori dan jenis transaksi lama

- **Task**: A1-02 SIMANJA; menutup audit **A02**.
- **Tanggal**: 2026-11-27.
- **Stack**: Flutter/Dart + Firebase (tidak berubah). **Commit manual oleh user**;
  tidak ada stage/commit/push/deploy pada tahap ini. Berhenti setelah tahap ini.
- **Pesan commit saran**: `fix(transactions): pertahankan kategori dan jenis lama`.

> Catatan referensi: dokumen audit sumber
> `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-frontend.md#a02`
> dan "prompt pembuka file anggota 1" **tidak ada di dalam repo** ini. Claim
> yang bergantung pada isi dokumen audit tersebut ditandai **BLOCKED** di bawah;
> pemenuhan kriteria lulus diuji langsung, tidak disimpulkan dari dokumen itu.
> (Prompt pembuka diterapkan sebagaimana diberikan: Flutter/Dart + Firebase
> tetap, commit manual oleh user.)

---

## 1. Root cause (temuan)

Di `frontend/lib/screens/transaction_page.dart`, `_TransactionFormSheetState._save()`
(versi baseline commit `2421808`):

1. **Kategori tak dikenal tidak bisa disimpan.**
   - `_selectedCategory == null` untuk kategori yang tidak ada di
     `CategoryMeta.knownCategories` (kategori lama tidak dikenal; `_unknownCategory`
     diisi nama asal), lalu `_save()` keluar dengan error
     `'Pilih kategori terlebih dahulu'`.
   - `FormField<CategoryMeta>.validator` `v == null ? 'Pilih kategori terlebih
     dahulu' : null` gagal saat `_formKey.currentState!.validate()`.
   - Petunjuk UI lama mengarahkan `'Pilih kategori baru untuk melanjutkan.'`
     (wajib memilih kategori baru) — bertentangan dengan syarat A1-02.
2. **Jenis transaksi selalu diturunkan ulang dari kategori.**
   `isIncome: cat.isIncome` dikirim pada setiap simpan. Mengubah hanya
   keterangan ikut mengirim ulang jenis berdasarkan `CategoryMeta.isIncome`
   kategori yang terpilih, sehingga:
   - kategori **tak dikenal** (tidak punya `CategoryMeta`) → `_selectedCategory`
     null; dan
   - kategori **dikenal tapi jenis legacy tidak selaras** (mis. `category='Gaji'`
     dikenal pemasukan tapi `isIncome=false` lama, atau `'Makan & Minum'` dikenal
     pengeluaran tapi `isIncome=true` lama) → jenis ditimpa mengikuti
     `CategoryMeta`, **bukan** `existing.isIncome`.
3. **Kategori/jenis asal tidak dipisah dari pilihan baru.** `_selectedCategory`
   dipakai sebagai keduanya; tidak ada `originalCategory`/`originalIsIncome`
   terpisah dan tidak ada penanda perubahan eksplisit pengguna.

## 2. Gate & batas (dipatuhi)

- **Jangan membuat model duplikat.** Tidak ada model baru; `TransactionModel`
  & `CategoryMeta` (`frontend/lib/models/transaction_model.dart`) dibaca apa
  adanya; `copyWith` mempertahankan `id`, `version`, `legacyDate`.
  Tidak ada perubahan `frontend/lib/repositories/transaction_repository.dart`
  (dibaca; `TransactionMapper.toMap`, `update`, `add`, `AppState.updateTransaction`
  tidak diubah). **Perubahan domain tambahan melalui handoff C** — tidak ada
  perubahan domain di tahap ini.
- **Scope awal**: `frontend/lib/screens/transaction_page.dart` + tes editor.
- **Prasyarat lokal A1-01** (lihat §5).
- Tidak membuat file anggota/tim baru; hanya `docs/` (diciptakan untuk catatan ini).

## 3. Perubahan yang dilakukan

Hanya **satu file kode** diubah + **satu file test** ditambah + dokumen ini.

### 3.1 `frontend/lib/screens/transaction_page.dart`

Memisahkan **kategori/jenis asal** dari **pilihan baru** dan menghentikan
penurunan ulang jenis dari kategori. Hunk eksak (relatif ke baseline `2421808`;
`git diff` penuh direkam pada percakapan; verifikasi `git diff` sebelum commit):

- **State baru** di `_TransactionFormSheetState` (setelah `CategoryMeta?
  _selectedCategory;`, sebelum `bool _saving`):
  - `String? _originalCategory;` — kategori asal dari `existing`.
  - `bool? _originalIsIncome;` — jenis asal dari `existing.isIncome`.
  - `bool _categoryChanged = false;` — true setelah pengguna **eksplisit** memilih
    kategori di dropdown.
- **`initState`**: set `_originalCategory = ex.category;` &
  `_originalIsIncome = ex.isIncome;` (kategori asal disimpan terpisah; `_selectedCategory`
  tetap hanya `match` kategori dikenal, null bila tak dikenal; `_unknownCategory`
  tetap menampilkan nama tak dikenal).
- **`_checkDirty`**: klausa kategori `(_selectedCategory != null && name != ex.category)`
  → `_categoryChanged`.
- **Dropdown `onChanged`**: set `_categoryChanged = true;` + `_unknownCategory = null;`
  (selain `_selectedCategory = v;`).
- **FormField validator**: `v == null ? ... : null` → `v == null && !_isEdit ? ... : null`
  (mode edit boleh `_selectedCategory == null`; mode tambah baru tetap wajib pilih).
- **`_unknownCategory` hint**: `'Pilih kategori baru untuk melanjutkan.'` →
  `'Kategori asal tetap disimpan jika tidak diubah.'`.
- **`_save()`**:
  - Guard kategori kosong `_selectedCategory == null → error` diganti:
    `if (_selectedCategory == null && !(_isEdit && !_categoryChanged)) { ...error... }`
    (edit tanpa perubahan kategori tetap boleh; tambah baru wajib pilih).
  - `final cat = _selectedCategory!;` → `final cat = _selectedCategory;`.
  - `category: cat.name` → `category: _effectiveCategory(cat)`.
  - `isIncome: cat.isIncome` → `isIncome: _effectiveIsIncome(cat)` (edit & tambah).
  - **Tidak ada** perubahan `id`, `amount`, `description`, `date`, `_createId`,
    `copyWith`, `addTransaction`, `updateTransaction`.
- **Getter/helper baru** (sebelum `_save()`):
  - `bool get _explicitCategoryChange => _categoryChanged && _selectedCategory !=
    null && _selectedCategory!.name != _originalCategory;`
  - `String _effectiveCategory(CategoryMeta? picked)`: perubahan kategori eksplisit
    → pilihan baru; edit tanpa perubahan kategori → kategori asal apa adanya
    (termasuk tak dikenal, tidak di-fallback); tambah baru → pilihan (wajib).
  - `bool _effectiveIsIncome(CategoryMeta? picked)`: **tidak diturunkan ulang dari
    kategori ketika hanya keterangan berubah**; perubahan kategori/jenis eksplisit
    → jenis mengikuti pilihan baru; edit tanpa perubahan kategori →
    `originalIsIncome` (termasuk kategori dikenal dengan jenis legacy tidak
    selaras); tambah baru → jenis pilihan kategori.
- `dart format` diterapkan; `flutter analyze` bersih.

### 3.2 `frontend/test/transaction_category_type_preservation_test.dart` (baru)

Regresi widget (**unknown / mismatched / explicit-change**) dengan **pemeriksaan
payload mutasi**: spy `_SpyTransactions extends MemoryTransactions` merekam
`update(uid,id,transaction)` & `add(transaction)`; payload diperiksa pada
`TransactionModel` yang dikirim ke repository **dan** peta mutasi efektif
`TransactionMapper.toMap(tx)` (`category`, `isIncome`, `amount`, plus `id` /
`update.id == transaction.id`, target tepat, transaksi lain tidak disentuh).
9 tes `testWidgets` (lihat §4). Tidak menyentuh tes existing; tidak membuat
model duplikat.

## 4. Kriteria lulus (cara diverifikasi)

- **Edit Biaya Khusus / isIncome=false mempertahankan kategori/jenis/ID/nominal**:
  tes unknown `category='Biaya Khusus'`, `isIncome=false`, `id='tx-biaya-khusus'`,
  `amount=50000`, ubah hanya keterangan → `update` sekali; payload `category=
  'Biaya Khusus'`, `isIncome=false`, `amount=50000`, `id` sama; `update.id ==
  transaction.id`; tidak ada error `'Pilih kategori terlebih dahulu'`. [lulus]
- **Kategori dikenal dengan jenis legacy tidak selaras tetap utuh**:
  `category='Gaji'` + `isIncome=false` (tetap `false`, tidak jadi `true`) dan
  `category='Makan & Minum'` + `isIncome=true` (tetap `true`, tidak jadi `false`)
  saat hanya keterangan berubah. [lulus]
- **Kategori tak dikenal tetap dapat disimpan jika tidak diubah sengaja**:
  `_selectedCategory==null`, validator mode edit lulus, `_categoryChanged=false`
  → kategori asal dipertahankan; hint `tidak dikenal` tampil. [lulus]
- **Tidak menurunkan ulang jenis dari kategori ketika hanya keterangan berubah**:
  `_effectiveIsIncome` hanya memakai `picked.isIncome` bila
  `_explicitCategoryChange`; jenis = `originalIsIncome`. [lulus]
- **Perubahan kategori/jenis eksplisit**:
  pilih kategori lain eksplisit (`Makan & Minum`→`Transportasi`, jenis sama) →
  kategori baru, ID & nominal utuh; pilih grup lawan (`Makan & Minum`→`Gaji`,
  pengeluaran→pemasukan) → `isIncome` ikut pilihan baru; kategori tak dikenal +
  pilih kategori eksplisit → kategori asal diganti. [lulus]
- **Edit daftar tersaring tepat target**: edit dari tab `Pengeluaran` hanya
  `update(id=...)` untuk transaksi itu; transaksi lain tidak disentuh; kategori
  tak dikenal & kategori dikenal mismatch di daftar tersaring tetap tepat target
  & jenis dipertahankan. [lulus]
- Tidak membuat model duplikat; tidak ada perubahan domain. [lulus]

## 5. Dependency & prasyarat

- **A1-01 (prasyarat lokal) — TERPENUHI.** `git log` `HEAD=2421808`
  `fix(transactions): pertahankan makna input nominal` mengubah
  `frontend/lib/screens/transaction_page.dart` + menambah
  `frontend/test/transaction_nominal_test.dart`; **baseline `flutter test`
  384/384 lulus** sebelum perubahan A1-02. Semantik nominal A1-01
  (`parseRupiah`, `_RupiahInputFormatter`) **tidak diubah**; suite
  `transaction_nominal_test.dart` tetap lulus. Bukti prasyarat A1-01 selain
  commit + tes di atas: **tidak ada** (lihat batas bukti).
- **Handoff C**: perubahan domain tambahan (model/repository/kontrak Firestore)
  **tidak dikerjakan**; diserahkan ke handoff C bila diperlukan.
- **Firebase**: tetap; tidak ada perubahan rules/struktur dokumen.

## 6. Baseline vs hasil tes (evidence)

Lingkungan: Flutter 3.47.2 stable / Dart 3.13.2, Windows.

| Tahap | Perintah | Hasil |
|---|---|---|
| Baseline (sebelum edit) | `flutter test` | **+384 All tests passed!** (exit 0) |
| A1-02 suite baru saja | `flutter test test/transaction_category_type_preservation_test.dart` | **+9 All tests passed!** |
| Gabungan baru + A1-01 | `flutter test test/transaction_category_type_preservation_test.dart test/transaction_nominal_test.dart` | **+29 All tests passed!** |
| Penuh (setelah edit) | `flutter test` | **+393 All tests passed!** (384 + 9, exit 0) |
| Statis | `flutter analyze lib test/transaction_category_type_preservation_test.dart` | **No issues found** |
| Format | `dart format` / `--set-exit-if-changed` | bersih |

Log uji disimpan sementara (`%TEMP%`), tidak dikomit.

## 7. Batas bukti (evidence limits)

- **Tes memakai repository in-memory** (`MemoryTransactions` + spy) di batas
  `TransactionRepository`, bukan **Firestore sungguhan**. Payload mutasi
  diperiksa hingga `TransactionMapper.toMap(tx)` (peta yang dikirim ke
  Firestore); **tidak** diuji ke Firebase live/emulator, rules Firestore, atau
  konkurensi versi (`RecordConcurrency.requireSame`) di backend.
- **Widget test** pada layar `_TransactionFormSheet`; tidak menguji seluruh app
  di perangkat sungguhan, locale produksi, atau migrasi data lama di Firestore.
- **Bukti `_explicitCategoryChange`**: perubahan jenis eksplisit diuji lewat
  memilih kategori **berbeda** di grup lawan; karena jenis terikat ke kategori di
  UI ini, tidak ada kontrol "jenis" terpisah. Re-pilih kategori yang **sama**
  (nama identik) tidak menghitung perubahan & mempertahankan data asal —
  interpretasi aman terhadap syarat "kategori dikenal dengan jenis legacy tidak
  selaras tetap utuh". Tidak diuji skenario produksi re-pilih nama sama.
- **Kriteria dari dokumen audit A02** tidak dapat dibandingkan baris-per-baris:
  dokumen audit sumber `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-
  frontend.md` **tidak ada di repo**; kriteria lulus dinilai dari teks tugas
  A1-02 yang diberikan. Claim yang memerlukan isi audit/anggota-1 file: **BLOCKED**.
- **Prompt pembuka anggota 1** "file anggota 1" tidak ditemukan di repo; prompt
  diterapkan sebagaimana diberikan. Claim tambahan dari file itu: **BLOCKED**.
- Snapshot `git status` memiliki **perubahan tak ter-commit pra-eksisting** yang
  **tidak disentuh**: `backend/package-lock.json` (terhapus) & generated
  `GeneratedPluginRegistrant.*` / `generated_plugin_registrant.*` /
  `generated_plugins.cmake`. Bukan bagian A1-02.
- Tidak ada klaim perilaku nyata Firestore offline/pending beyond yang sudah
  dilakukan kode existing; tidak ada perubahan baru di `transaction_repository`.

## 8. Status

- **Status: SELESAI (implementasi + tes + dokumentasi).**
- **BLOCKED**: (a) verifikasi literal vs dokumen audit A02 (sumber tidak ada di
  repo); (b) verifikasi vs "prompt pembuka file anggota 1" (file tidak ada di
  repo); (c) klaim integrasi Firestore sungguhan (tidak diuji live). Semua
  kriteria lulus yang ditulis pada tugas A1-02 **lulus**.
- **Reservasi file bersama** (akan disentuh/di-stage user; jangan kerjakan
  paralel tanpa koordinasi): `frontend/lib/screens/transaction_page.dart`
  (bersama task A1 lain), `frontend/test/transaction_category_type_preservation_test.dart`
  (baru), `docs/a1-02-pertahankan-kategori-dan-jenis-transaksi-lama.md` (baru).
  Model/repository **tidak** diubah (`transaction_model.dart`,
  `transaction_repository.dart`, `app_state.dart` read-only di sini).

## 9. Handoff

- **Berhenti setelah tahap ini.** Tidak stage, tidak commit, tidak push, tidak
  deploy, tidak lanjut tahap berikutnya. **Tidak ada diff kosong** (ada diff
  nyata; tidak membuat commit kosong).
- **Commit manual oleh user.** Pesan saran: `fix(transactions): pertahankan
  kategori dan jenis lama`. Stage **hanya** file A1-02 di atas; jangan ikutkan
  perubahan pra-eksisting (`backend/package-lock.json`, generated plugin
  registrant) atau perubahan anggota lain.
- **Perintah commit (dijalankan user, bukan saya):** lihat blok pada ringkasan
  akhir percakapan.
- **Handoff C**: perubahan domain/model/repository tambahan → handoff C.
- **Rollback**: `git restore frontend/lib/screens/transaction_page.dart`; hapus
  `frontend/test/transaction_category_type_preservation_test.dart` & doc ini.
- Re-verifikasi pasca-commit: `flutter test` (ekspektasi +393) &
  `flutter analyze` bersih.
