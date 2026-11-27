# A1-03 — Samakan batas validasi editor dan domain

- **Task**: A1-03 SIMANJA; menutup audit **A03**.
- **Tanggal**: 2026-11-27.
- **Stack**: Flutter/Dart + Firebase (tidak berubah). **Commit manual oleh user**;
  tidak ada stage/commit/push/deploy pada tahap ini. Berhenti setelah tahap ini.
- **Pesan commit saran**: `fix(forms): selaraskan batas input dengan repository`.

> Catatan referensi: dokumen audit sumber
> `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-frontend.md#a03`
> dan "prompt pembuka file anggota 1" **tidak ada di dalam repo** ini. Claim
> yang bergantung pada isi dokumen audit itu ditandai **BLOCKED**; kriteria
> lulus diuji langsung. (Prompt pembuka diterapkan sebagaimana diberikan.)

---

## 1. Prasyarat lokal: A1-02

**A1-02 terpenuhi di working tree.** Perubahan A1-02 (`_originalCategory`/
`_originalIsIncome`, `_effectiveCategory`, `_effectiveIsIncome`, kategori tak
dikenal, `frontend/test/transaction_category_type_preservation_test.dart`,
`docs/a1-02-...`) sudah diterapkan di `frontend/lib/screens/transaction_page.dart`
dan suite lengkap lulus (**+393**) sebelum A1-03. Catatan jujur: A1-02
**belum di-commit** oleh user; pada tahap ini saya tidak commit. **Baseline
A1-03 = +393 All tests passed!** sebelum edit A1-03. Jika memerlukan
committed prasyarat, commit A1-02 lebih dulu (`fix(transactions): pertahankan
kategori dan jenis lama`), baru A1-03.

## 2. Gate & batas (dipatuhi)

- **Jangan melonggarkan server agar editor yang salah terlihat cocok.**
  Tidak ada perubahan server/domain/repository. Kontrak dibaca **read-only**:
  `frontend/lib/models/transaction_model.dart` (`TransactionModel`,
  `TransactionMapper` di repository), `frontend/lib/repositories/transaction_repository.dart`,
  `frontend/lib/models/user_profile.dart` (`UserProfile.parseIncome`, `toMap`,
  `maxRupiah`, validasi), `frontend/lib/repositories/profile_repository.dart`,
  `frontend/lib/core/app_state.dart`. Editor **diselaraskan ke kontrak**, bukan
  sebaliknya. **Jangan membuat model duplikat.**
- **Scope awal**: `frontend/lib/screens/transaction_page.dart`;
  `frontend/lib/screens/profile_page.dart`; tes form; kontrak model/repository
  read-only.
- **Perubahan domain tambahan** → handoff C; tidak dikerjakan.

## 3. Root cause (A03)

- **Minimum dua karakter keterangan vs kontrak nonempty.** Keterangan editor
  `if (v.trim().length < 2) return 'Keterangan minimal 2 karakter';`, sedangkan
  `TransactionMapper.toMap` hanya mensyaratkan `description.trim().isNotEmpty`
  (+ `trim().length <= 1000`). Keterangan satu karakter ditolak editor tapi
  sah domain.
- **`maxLength: 1000` mentah vs panjang ter-trim domain.** `maxLength` memotong
  input 1001→1000 diam-diam, sehingga **1001 invalid** tidak dapat terbentuk
  di editor, dan batas mentah tidak selaras dengan `trim().length <= 1000`.
- **Pesan berbeda-beda.** Pendapatan profil: inline `'Pendapatan harus berupa
  angka bulat non-negatif'` vs `_save` `'Pendapatan harus berupa angka bulat
  rupiah yang valid'` vs domain `'Pendapatan harus berupa rupiah bulat
  non-negatif.'`. Keterangan pesan tidak konsisten.
- **Pendapatan profil nol.** `_pendapatanCtrl` initState `monthlyIncome > 0 ?
  ... : ''` mengosongkan tampilan untuk **0** (kosong→0 saat simpan, nilai
  tetap 0, tapi tidak eksplisit; perlu diuji). Kriteria A1-03: 0 sah &
  dipertahankan; negatif/pecahan invalid.
- **Done + tap ganda & input setelah gagal.** `textInputAction: done` tanpa
  `onFieldSubmitted`; `_saving`/`_isSaving` guard ada tapi perlu diverifikasi;
  input tidak boleh dibersihkan saat failure. Kriteria: submit ganda paling
  banyak satu operasi; failure mempertahankan input.

## 4. Perubahan yang dilakukan

**Hanya dua file kode** + **satu file test** + dokumen ini.

### 4.1 `frontend/lib/screens/transaction_page.dart`

- **Keterangan (`_TransactionFormSheet`):**
  - **Hapus** `if (v.trim().length < 2) return 'Keterangan minimal 2 karakter';`
    → keterangan **satu karakter** sah; kontrak **non-empty**.
  - **Hapus `maxLength: 1000`**; pertahankan validator `v.trim().length > 1000
    → 'Keterangan maksimal 1000 karakter'`. Batas selaras `TransactionMapper.
    toMap` `description.trim().length <= 1000`; **1001 invalid (tidak diam-diam
    dipotong)**; whitespace-only `trim().isEmpty → 'Keterangan wajib diisi'`;
    disimpan `trim()`.
  - Update komentar A03 → A1-03. Pesan field tetap `'Keterangan wajib diisi'` /
    `'Keterangan maksimal 1000 karakter'`.
- **Done + submit ganda:** `onFieldSubmitted: (_) => _save(),` pada field
  Jumlah (`textInputAction: done`). `_save()` sudah `if (_saving) return;` +
  `setState(_saving=true)` sinkron + `ElevatedButton onPressed: _saving ? null
  : _save` + `AppState` `_mutatingIds`. **Submit ganda (Done + tap / tap
  ganda) paling banyak satu operasi.** Tidak ada perubahan `_saving`.
- **Failure mempertahankan input:** catch `_save` set `_saveError` + `_saving=
  false`; controller **tidak dibersihkan**; bisa retry. Tidak ada perubahan.
- **Tidak ada perubahan** `_effectiveCategory`/`_effectiveIsIncome` (A1-02),
  `id`, `amount`, `date`, `copyWith`, mutasi repository.

### 4.2 `frontend/lib/screens/profile_page.dart`

- **Pendapatan profil nol dipertahankan:** `_pendapatanCtrl` initState
  `s.monthlyIncome > 0 ? ... : ''` → `s.monthlyIncome.toInt().toString()`
  (**0 → '0'**, bukan dikosongkan; kosong→0 saat simpan; `income ?? ...` pakai
  `0` bukan fallback `_editBase`). `UserProfile.toMap` `monthlyIncome.toInt()`
  `>=0` integer. `parseIncome('0')=0`, `parseIncome('')=0`.
- **Pesan pendapatan selaras:** `_save` `_saveError 'Pendapatan harus berupa
  angka bulat rupiah yang valid'` → **`'Pendapatan harus berupa angka bulat
  non-negatif'`**, sama dengan inline validator. (Domain read-only
  `'Pendapatan harus berupa rupiah bulat non-negatif.'`.)
- **Profil pendapatan 0 sah; negatif/pecahan invalid** (`parseIncome` `null`
  → invalid; `-`/`,`/`.` non-ribuan ditolak; `_formKey.validate()` + `_save`
  recheck). **Submit ganda** `_isSaving || profileSaving` + `profile-save
  onPressed null` → paling banyak satu `save`. **Failure mempertahankan input**
  (`_saveError`, `_isSaving=false`, controller tidak dibersihkan).
- **Tidak ada perubahan** `UserProfile`, `MemoryProfiles`, `AppState.updateProfile`.

### 4.3 `frontend/test/form_validation_bounds_test.dart` (baru)

12 widget test + **repository spy** (`_SpyTransactions extends MemoryTransactions`
rekam `add`/`update`; `MemoryProfiles.saves`/`saveFailure`/`pendingSave`;
payload efektif `TransactionMapper.toMap`):

- **A. Keterangan boundary:** satu karakter sah; panjang **1000** sah; panjang
  **1001** invalid (input tidak dipotong, `maxLength` dilepas); **kosong**
  invalid; **whitespace-only** invalid; tidak ada mutasi saat invalid; pesan
  `Keterangan wajib diisi`/`Keterangan maksimal 1000 karakter`, **tidak ada
  `Keterangan minimal 2 karakter`**; kontrak domain `TransactionMapper.toMap`
  tetap menolak kosong/whitespace & 1001, menerima 1 & 1000.
- **B. Submit ganda & failure (transaksi):** **tap ganda** paling banyak satu
  `add` + satu `writes`; **Done + tap** (`testTextInput.receiveAction(
  TextInputAction.done)` + tap) paling banyak satu; **failure** (`writeFailure`)
  tampil `Gagal menyimpan`, **input Keterangan/Jumlah dipertahankan**,
  `committedWrites=0`, retry setelah failure berhasil.
- **C. Profil pendapatan:** **pendapatan 0** profil sah & dipertahankan + field
  menampilkan `'0'`; **0 eksplisit** sah; **negatif** invalid; **pecahan**
  (`,`/`.`) invalid; pesan `'Pendapatan harus berupa angka bulat non-negatif'`;
  **submit ganda** paling banyak satu `save`; **failure** (`saveFailure`)
  `_saveError` + **input pendapatan dipertahankan**.

`dart format` + `flutter analyze` bersih. Tidak menyentuh test existing; tidak
membuat model duplikat.

## 5. Kriteria lulus (dipetakan ke verifikasi)

- **Keterangan satu karakter sah** (`a`; trimmed len 1; `TransactionMapper`
  `isNotEmpty`). [lulus]
- **Panjang 1000 sah** (trimmed len 1000; `<=1000`; `maxLength` dilepas,
  payload 1000). [lulus]
- **Kosong invalid** (`''`, `trim().isEmpty → 'Keterangan wajib diisi'`; domain
  `isNotEmpty`). [lulus]
- **Whitespace invalid** (`'   '`→trim empty; domain `trim().isNotEmpty`;
  whitespace pendapatan→`trim`+`parseIncome`→ kosong→0 hanya untuk income yang
  memang opsional-nol; keterangan whitespace tetap invalid). [lulus keterangan]
- **Panjang 1001 invalid** (validator `>1000`; domain `>1000`; tidak dipotong
  oleh `maxLength`). [lulus]
- **Tidak ada minimum dua karakter keterangan** vs kontrak nonempty. [lulus]
- **Profil pendapatan 0 sah** + dipertahankan; field `'0'`; `parseIncome('0')
  =0`; `parseIncome('')=0`; `monthlyIncome>=0` integer; `_save`→`0`. [lulus]
- **Negatif invalid** (`-1`; `<0`; regex `-` ditolak; domain `<0`; `UserProfile
  .toMap` `<0`). [lulus]
- **Pecahan invalid** (`1,5`,`1.5`; `amount != roundToDouble`; domain; `1.500`
  ribuan bulat `1500` sah — bukan pecahan). [lulus]
- **Submit ganda paling banyak satu operasi** (transaksi `_saving` +
  `onFieldSubmitted` + tombol + `_mutatingIds`; profil `_isSaving` +
  `profileSaving` + tombol; **Done + tap**; tap ganda; repository spy `adds`/
  `saves`/`writes` `==1`). [lulus]
- **Failure mempertahankan input** (transaksi & profil; `_saving`/`_isSaving`
  reset; controller tidak dibersihkan; `_saveError`; retry). [lulus]
- **Batas selaras editor & domain**; **tidak melonggarkan server**; **pesan
  field selaras**. [lulus]

## 6. Baseline vs hasil tes (evidence)

Lingkungan: Flutter 3.47.2 stable / Dart 3.13.2, Windows.

| Tahap | Perintah | Hasil |
|---|---|---|
| Baseline A1-03 (sudah +A1-02, sebelum edit A1-03) | `flutter test` | **+393 All tests passed!** |
| Suite A1-03 baru saja | `flutter test test/form_validation_bounds_test.dart` | **+12 All tests passed!** |
| Penuh (setelah edit) | `flutter test` | **+405 All tests passed!** (393 + 12, exit 0) |
| Statis | `flutter analyze lib test/form_validation_bounds_test.dart` | **No issues found** |
| Format | `dart format` / `--set-exit-if-changed` | bersih |

Regresi terkait (sudah di suite penuh): A1-01 `transaction_nominal_test.dart`
(nominal), A1-02 `transaction_category_type_preservation_test.dart`
(kategori/jenis), `profile_page_test.dart`, `profile_state_test.dart`
(`UserProfile.parseIncome`, toMap, income), `transaction_repository_test.dart`,
`transaction_sync_test.dart`, `record_conflict*`. Log sementara `%TEMP%`, tidak
dikomit.

## 7. Batas bukti (evidence limits)

- **Tes repository spy in-memory** (`MemoryTransactions`, `MemoryProfiles`),
  bukan **Firestore/Firebase sungguhan**; payload diperiksa hingga
  `TransactionMapper.toMap` & `UserProfile.toMap`/`changesSince`; **tidak** diuji
  live Firestore, rules, atau konkurensi backend. **Tidak melonggarkan server**
  (domain read-only & tidak diubah).
- **Widget test**; tidak diuji perangkat sungguhan, keyboard sistem sungguhan,
  atau locale produksi. **Done** diuji via `testTextInput.receiveAction(
  TextInputAction.done)` (mekanik `onFieldSubmitted` Flutter), tidak keyboard
  hardware.
- **"pendapatan nol dipertahankan"**: diuji 0 profil → field `'0'` → simpan →
  `monthlyIncome=0` + nilai profil 0; tidak ada perubahan server. 
- **Pesan** editor selaras secara internal (keterangan; pendapatan inline +
  `_save`); string domain read-only tidak diubah, tidak diklaim identik karakter
  per karakter.
- **Audit A03 sumber** `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-
  frontend.md#a03` **tidak ada di repo**; kriteria dinilai dari teks A1-03;
  claim vs isi audit/anggota-1 file: **BLOCKED**.
- **Prasyarat A1-02** terpenuhi di working tree; **A1-02 belum di-commit**
  oleh user (lihat §1); urutan commit disarankan A1-02 → A1-03.
- Snapshot `git status` memiliki perubahan pra-eksisting tak ter-commit yang
  **tidak disentuh**: `backend/package-lock.json`, generated plugin registrant.

## 8. Status

- **Status: SELESAI** (implementasi + 12 test + docs); kriteria A1-03 **lulus**.
- **BLOCKED**: (a) verifikasi literal vs dokumen audit A03 (sumber tidak ada);
  (b) vs "prompt pembuka file anggota 1" (file tidak ada); (c) klaim
  integrasi Firestore sungguhan (tidak diuji live).
- **Reservasi file bersama** (jangan kerjakan paralel tanpa koordinasi):
  `frontend/lib/screens/transaction_page.dart`, `frontend/lib/screens/
  profile_page.dart`, `frontend/test/form_validation_bounds_test.dart` (baru),
  `docs/a1-03-selaraskan-batas-validasi-editor-dan-domain.md` (baru). Model/
  repository read-only. Build di atas **A1-01 + A1-02**.

## 9. Handoff

- **Berhenti setelah tahap ini.** Tidak stage/commit/push/deploy; tidak lanjut
  tahap berikutnya. **Tidak ada diff kosong.**
- **Commit manual oleh user.** Pesan saran `fix(forms): selaraskan batas input
  dengan repository`. Stage **hanya** file A1-03; **commit A1-02 lebih dulu**
  (working tree) bila prasyarat committed diperlukan; jangan ikutkan
  perubahan pra-eksisting / anggota lain. Perintah contoh diberikan pada
  ringkasan akhir percakapan.
- **Handoff C**: perubahan domain tambahan.
- **Rollback**: `git restore frontend/lib/screens/transaction_page.dart
  frontend/lib/screens/profile_page.dart`; hapus test & doc baru.
- Re-verifikasi pasca-commit: `flutter test` (+405) & `flutter analyze` bersih.
