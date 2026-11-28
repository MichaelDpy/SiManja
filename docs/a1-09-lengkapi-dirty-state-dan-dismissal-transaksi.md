# A1-09 — Lengkapi dirty state dan dismissal transaksi

- **Task**: A1-09 SIMANJA; menutup audit **A14**.
- **Tanggal**: 2026-11-28.
- **Stack**: Flutter/Dart + Firebase (tidak berubah). **Commit manual oleh user**;
  tidak ada stage/commit/push/deploy pada tahap ini. Berhenti setelah tahap ini.
- **Pesan commit saran**: `fix(transactions): lindungi draft kategori dan tanggal`.
- **Gate & batas**: **C05/C08 direuse** (gate offline-pending & sesi/UID switch
  yang sudah ada; tidak ada perubahan `AppState`, repository, atau rules);
  **tidak membuat antrean offline baru**; **tidak ada perubahan domain**
  (`transaction_model.dart`, `transaction_repository.dart`, `app_state.dart`,
  `session_gate.dart`, `transaction_sync_status.dart` read-only).

> Catatan referensi: dokumen audit sumber
> `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-frontend.md#a14`
> dan "prompt pembuka file anggota 1" **tidak ada di dalam repo** ini (dicari
> rekursif `docs/`, root, dan seluruh workspace). Claim yang bergantung pada isi
> dokumen audit / prompt pembuka tersebut ditandai **BLOCKED** di bawah;
> pemenuhan kriteria lulus diuji langsung terhadap teks tugas A1-09, tidak
> disimpulkan dari dokumen itu. (Prompt pembuka diterapkan sebagaimana
> diberikan: Flutter/Dart + Firebase tetap, commit manual oleh user.)

---

## 1. Prasyarat lokal

- **A1-02 (prasyarat lokal) — TERPENUHI.** Kategori asal & jenis legacy
  dipisah dari pilihan baru (`_originalCategory`, `_originalIsIncome`,
  `_categoryChanged`, `_explicitCategoryChange`, `_effectiveCategory`,
  `_effectiveIsIncome`), kategori tak dikenal tetap bisa disimpan. Tidak
  diubah di A1-09; suite `transaction_category_type_preservation_test.dart`
  tetap lulus. Bukti di `docs/a1-02-pertahankan-kategori-dan-jenis-transaksi-lama.md`.
- **A1-04 (prasyarat lokal) — TERPENUHI.** Tanggal kalender R-DATE +
  `CalendarDate`, date-picker clamp (`firstDate`/`lastDate`), cancel kalender
  tidak mengubah state. Tidak diubah di A1-09; suite
  `transaction_date_picker_test.dart` tetap lulus. (Dokumen `a1-04-*` sendiri
  tidak ada di `docs/`; diverifikasi lewat kode + tes.)
- **C05 (offline/pending retry)** — `frontend/tool/c05_offline_smoke.dart`,
  `offline_sync_test.dart`, `offline_sync_widget_test.dart`, `SyncFailure`,
  `AppState._mutatingIds`, `pendingMutations`, `transactionsHasPendingWrites`;
  suite `offline_sync_*` tetap lulus; **tidak diubah, hanya direuse**.
- **C08 (session/UID switch)** — `frontend/tool/c08_session_smoke.dart`,
  `session_isolation_test.dart`, `session_cache_policy_test.dart`,
  `AppState._sessionRevision`, `_clearUserData`, `sessionUid`,
  `SessionGate.pushNamedAndRemoveUntil`, `mounted`; suite `session_*` tetap
  lulus; **tidak diubah, hanya direuse**.

## 2. Root cause (temuan)

Di `frontend/lib/screens/transaction_page.dart`, `_TransactionFormSheetState`
(versi baseline `HEAD=b4bf936`):

1. **Dirty tracking tidak lengkap.** `_checkDirty()`:
   - **transaksi baru** (`existing == null`): hanya mengecek
     `_descCtrl.text.trim().isNotEmpty || _amountCtrl.text.trim().isNotEmpty`.
     **Kategori & tanggal yang diubah TIDAK dihitung dirty.** Karena
     `PopScope.canPop = !_saving && !_isDirty`, sebuah transaksi baru yang
     hanya kategori / tanggal diubah bisa ditutup (Back / tap luar) **tanpa
     konfirmasi** → **draft kategori/tanggal hilang tanpa keputusan.**
     (Diverifikasi empiris: scratch test baseline → `CAT_ONLY dialog=false`.)
   - **edit**: tanggal dibanding `CalendarDate.same`, nominal string, dan
     `_categoryChanged` — tetapi `_categoryChanged` **bendera** tidak membanding
     nilai kategori efektif terhadap kategori asal (re-pilih kategori sama
     dihitung dirty); tidak ada baseline snapshot eksplisit.
2. **Swipe modal melewati guard.** `_showFormSheet` memakai
   `showModalBottomSheet` default `enableDrag: true`. Pada Flutter 3.47.2,
   `_ModalBottomSheet` drag-to-close memanggil **`Navigator.pop(context)`
   imperatif** (`bottom_sheet.dart` `onClosing`), sedangkan **`Navigator.pop`
   TIDAK memeriksa `Route.popDisposition`** (hanya `Navigator.maybePop`
   memeriksa; lihat `navigator.dart` `_RouteEntry.pop(imperativeRemoval:true)`).
   Komentar lama `// A14: intersep Back/swipe ...` **tidak benar untuk swipe**:
   **swipe-down menutup sheet dirty tanpa konfirmasi & tanpa keputusan**, dan
   bisa memotong pending. (Diverifikasi empiris: scratch test baseline →
   `SWIPE sheetOpen=false dialog=false`.) **Back** & **tap luar** (barrier →
   `Navigator.maybePop`) **sudah** diintersepsi `PopScope`.
3. **Tidak ada state model eksplisit.** Tidak ada pembedaan
   clean/dirty/pending; tidak ada close aksi eksplisit; tidak ada reuse satu
   titik `_requestClose`.
4. **Pending (`_saving`)** sudah: `if (_saving) return;`, `_mutatingIds`,
   `canPop=false`, snackbar `'...permintaan belum dibatalkan.'`, `_createId`
   stabil, draft dipertahankan. Tetapi swipe bisa melewati (poin 2), dan
   **`_save()` men-`setState(_saveError)` saat sesi berubah** (`_mutate`
   melempar `StateError('Sesi telah berubah.')`→`SyncFailure`) → potensi
   **feedback sesi lama**; pada jalur sukses `_saving` tidak direset bila sesi
   berubah. **createId stabil & tidak ada write ganda sudah ada**
   (`_createId ??=`, `_mutatingIds`, `RecordConcurrency.confirmsRetry`,
   `SessionGate` menutup form UID lama, `mounted`); tidak ada klaim cancel RPC.
5. **Cancel/approve discard** `_confirmDiscard` sudah mempertahankan input
   (`Navigator.pop(ctx,false)` → no-op) & `Navigator.pop(context)` bila
   `shouldDiscard==true`, tetapi tidak memeriksa **`_saving`** (tidak relevan
   karena pending diblokir terpisah) dan tidak memeriksa **perubahan sesi**
   saat dialog terbuka.

## 3. Perubahan yang dilakukan

Scope awal terpenuhi. **Hanya satu file kode diubah** +
**satu file test ditambah** + **satu test file diperluas** + dokumen ini.
Tidak ada perubahan model/domain/repository/`AppState`.

### 3.1 `frontend/lib/screens/transaction_page.dart`

- **`enum TransactionFormDismissState { clean, dirty, pending }`** (baru,
  publik; dipakai di `canPop` & `_requestClose`).
- **`_TransactionPageState._showFormSheet`** (`showModalBottomSheet`):
  tambah `isDismissible: true` (tap luar→`Navigator.maybePop`→`PopScope`) +
  **`enableDrag: false`** (drag SDK memanggil `Navigator.pop` imperatif yang
  melewati `PopScope`; dinonaktifkan & swipe ditangani sendiri).
- **Snapshot baseline** (`_initialDescription`, `_initialAmount`,
  `_initialDate`, `late final`; diisi di `initState` SETELAH controller &
  `_selectedDate` di-set). `_initialDate = _selectedDate;`.
- **`_checkDirty()`** ditulis ulang:
  - keterangan `_descCtrl.text.trim() != _initialDescription`;
  - jumlah `_amountCtrl.text.trim() != _initialAmount`;
  - tanggal `!CalendarDate.same(_selectedDate, baselineDate)`;
    `baselineDate = _isEdit ? widget.existing!.date : _initialDate;`;
  - kategori `_categoryDirty`.
  - **A1-09: transaksi baru yang HANYA kategori / tanggal berubah → dirty.**
- **`_categoryDirty`** (getter baru): `_categoryChanged` wajib; edit →
  `_selectedCategory?.name != _originalCategory`; **transaksi baru →
  `_selectedCategory != null`.** Kategori asal tak dikenal tetap *clean*
  selama `_categoryChanged=false`; re-pilih kategori sama tidak dirty.
- **`_dismissState`** (getter baru): `pending` bila `_saving`; `dirty` bila
  `_isDirty`; selain itu `clean`. Recompute via `_updateDirty()`
  (listener `_onFieldChanged`, `_pickDate`, dropdown `onChanged`).
- **`_requestClose()`** (baru; satu titik masuk): **pending→`_showPendingSnack()`
  (tidak menutup, TIDAK menjanjikan cancel RPC)**; **dirty→`_confirmDiscard()`**;
  **clean→`Navigator.pop(context)`**. `if (!mounted) return;`.
- **`_showPendingSnack()`** (baru): `clearSnackBars` + snackbar
  `'Penyimpanan masih berjalan. Tunggu hasil dari server; permintaan belum
  dibatalkan.'` (teks sama; **tidak** klaim pembatalan).
- **`PopScope`**: `canPop: _dismissState == TransactionFormDismissState.clean`
  (hanya clean pop langsung); `onPopInvokedWithResult`: `if (didPop) return;`
  → `_requestClose();`. Berlaku untuk **Back, tap luar, close, swipe**.
- **Close aksi eksplisit** (baru): `IconButton(key:
  Key('close-transaction-form'), tooltip:'Tutup', icon:Icons.close,
  onPressed: _saving ? null : _requestClose)`. Judul tetap; header Row
  `Expanded(title)`.
- **Swipe-down** (baru): `GestureDetector(key:
  Key('transaction-sheet-swipe-handle'), behavior: opaque, onVerticalDragEnd:
  velocity > _kSheetSwipeDismissVelocity (250 px/s) → _requestClose())` pada
  handle bar; handle `margin.right=48` agar tidak tabrakan tombol tutup.
  `const double _kSheetSwipeDismissVelocity = 250;`.
- **`_confirmDiscard()`**: tambah `final revision =
  AppState.instance.sessionRevision;`; `.then`: hanya `shouldDiscard==true`
  → `mounted` → `AppState.instance.sessionRevision == revision` →
  `Navigator.pop(context)`. **Cancel/`Lanjut Edit`/barrier dialog/null →
  input dipertahankan**; **Buang→menutup form.** (imperative `Navigator.pop`
  dipakai sengaja karena canPop=false saat dirty.)
- **`_save()`** (`Future<void>`):
  - **`if (_saving) return;` SINKRON di paling awal** (sebelum
    `setState(_saveError=null)`) — pending tidak memulai write kedua; (guard
    lama setelah parse tetap dipertahankan efektif).
  - **snapshot sesi** `revision = appState.sessionRevision; sessionUid =
    appState.sessionUid;` + `bool sessionActive()`. `AppState.instance` →
    `appState`.
  - **createId stabil**: `id: _createId ??= appState.generateId(),`
    (tidak berubah; tidak di-reset; **tidak menjanjikan cancel RPC**).
  - **sukses**: `if (!mounted) return; if (!sessionActive()) { setState(()
    => _saving=false); return; }` (**tidak ada pop/feedback sesi lama**);
    lalu `Navigator.pop(context)` + snackbar `'Transaksi
    diperbarui/ditambahkan'`. **Tidak ada feedback sesi lama.**
  - **catch**: `if (!mounted) return;`; `if (sessionActive())` →
    `_saving=false + _saveError='Gagal menyimpan: $e'`; **else `_saving=
    false` tanpa `_saveError`**; **draft & `_createId` dipertahankan;
    retry tidak membuat write ganda**; **tidak ada feedback sesi lama.**
  - validasi/parse kategori (`_selectedCategory == null && !(_isEdit &&
    !_categoryChanged)`, `_formKey.validate()`, `parseRupiah`) **tidak
    mengubah** (A1-01/A1-02/A1-03), **tidak** menyentuh `_saving`.
- **Tidak diubah**: `_RupiahInputFormatter`, `parseRupiah`, validator,
  `_effectiveCategory`, `_effectiveIsIncome`, `_explicitCategoryChange`,
  `_originalCategory`, `_originalIsIncome`, `_categoryChanged`, `_saving`
  semantik, `_saveError`, `_isEdit`, `_unknownCategory`, `_pickDate`,
  `CalendarDate`, model, repository, `AppState`, `SessionGate`,
  `TransactionSyncStatus`. `dart format`, `flutter analyze` bersih.

### 3.2 `frontend/test/transaction_dismissal_test.dart` (baru, 15 tes)

Widget test `SimanjaApp` + `MemoryTransactions` + `MemoryProfiles` +
`SessionAuth`, `initializeDateFormatting('id_ID')`, view 412×915@1.0. Tanpa
mengubah tes existing.

- **clean state** (4): transaksi baru bersih + **Back** / **close** /
  **tap luar barrier** / **swipe-down** → menutup tanpa konfirmasi, no write.
- **dirty tracking** (7): transaksi baru **hanya kategori**→dirty;
  **hanya tanggal**→dirty; **kategori+tanggal tanpa keterangan/jumlah**→dirty;
  **cancel discard (`Lanjut Edit`) mempertahankan kategori + tanggal + draft**
  & tidak menulis; **cancel discard kategori-only lalu simpan mempertahankan
  pilihan**; **discard disetujui (`Buang`) menutup form tanpa write**;
  **cancel discard via barrier dialog mempertahankan input**.
- **dirty dismissal actual** (4): saat dirty — **Back** / **close** /
  **tap luar** / **swipe-down** sama-sama memakai guard `_confirmDiscard`;
  sheet tetap; `Buang` menutup.

### 3.3 `frontend/test/offline_sync_widget_test.dart` (diperluas, +2 tes; existing +2 tetap)

- **state pending** (1): `_saving` + `MemoryTransactions.pendingWrite` —
  **Back / close(disabled) / tap luar / swipe-down diblokir**; **tidak ada
  discard dialog**; **tidak ada `'Transaksi ditambahkan'`**; snackbar
  **`'permintaan belum dibatalkan'`** (**tidak menjanjikan cancel RPC**);
  `pendingMutations==1`, `committedWrites==0`, **tidak ada write ganda**;
  setelah `pendingWrite.complete()` → `committedWrites==1` +
  `'Transaksi ditambahkan'`; `takeException()==null`.
- **UID switch saat pending** (1): `_saving` + `AppState.clearSession()`
  (sessionRevision++, sessionUid→null) saat pending → `pendingWrite.complete()`
  → **`attemptedIds` panjang 1 (tidak ada write kedua / tidak ada write untuk
  sesi baru)**; **tidak ada `'Transaksi ditambahkan'`**; **tidak ada
  `'Gagal menyimpan'`**; **tidak ada `'Buang perubahan?'`**; **tidak ada
  feedback sesi lama**; `takeException()==null`.
- **Existing tetap lulus**: `lost ack mempertahankan form dan ID; retry
  tidak membuat transaksi kedua` (`SyncFailure.mayHaveCommitted`,
  `_saveError` `'Hasil penyimpanan belum dapat dipastikan...'`, **form
  tidak menutup**, **tidak ada `'Transaksi ditambahkan'`** sebelum ack,
  draft dipertahankan, `_createId` stabil `attemptedIds[0]==attemptedIds[1]`,
  retry → `committedWrites==1`, `'Transaksi ditambahkan'`); `request berjalan
  mengunci form dan Back tidak dianggap cancel write` (fields disabled,
  `pendingMutations==1`, Back→snackbar `'permintaan belum dibatalkan'`,
  no cancel, complete→`committedWrites==1`, snackbar).
- **Tes pending/retry existing lain** (tidak disentuh) tetap lulus:
  `offline_sync_test.dart` (lost-ack same-id no-dup, restart no-queue,
  pending vs local vs server-confirmed, no replay, reconcile, status local
  pending, "Muat data tidak mengulang write"), `record_conflict_widget_test.dart`
  (`form transaksi mempertahankan draft dan tidak menutup saat conflict`),
  `form_validation_bounds_test.dart` (submit ganda ≤1 op, Done+tap ≤1 op,
  failure mempertahankan input & retry), `transaction_sync_test.dart`
  (CRUD + logout/login ulang dua akun), `session_isolation_test.dart`,
  `session_cache_policy_test.dart`, `session_gate_test.dart`, C05/C08 smoke.

## 4. Kriteria lulus (cara diverifikasi) — A1-09

- **Draft kategori/tanggal tidak hilang tanpa keputusan**: transaksi baru
  yang hanya kategori / tanggal diubah = dirty; semua dismissal (Back/close/
  tap luar/swipe) memakai `_requestClose`; swipe tidak melewati `PopScope`
  (`enableDrag:false` + handler); pending tidak menutup. [lulus]
- **Transaksi baru hanya kategori berubah → dirty**. [lulus, tes]
- **Transaksi baru hanya tanggal berubah → dirty**. [lulus, tes]
- **Clean/dirty/pending ditetapkan pada Back/close/tap luar/swipe modal
  aktual**: `TransactionFormDismissState` + `canPop=clean` + `_requestClose`;
  **Gesture/widget dismissal aktual** diuji (Back `handlePopRoute`, close
  `Key('close-transaction-form')`, tap luar `tapAt`, swipe `fling` pada
  `Key('transaction-sheet-swipe-handle')`). [lulus, tes]
- **Cancel discard menjaga input; discard disetujui menutup form**:
  `Lanjut Edit`/`false`/barrier-null → tidak ada perubahan; `Buang`→
  `Navigator.pop`; no write; `_saving` tidak mengubah; `_saveError` tidak
  diubah. [lulus, tes]
- **Pending**: `_saving` + `pendingMutations` + `_mutatingIds`;
  `canPop=false`; dismissal diblokir; close dinonaktifkan; pending snackbar;
  **tidak ada write ganda**; **tidak ada klaim cancel RPC**; `_saving`
  di-reset. [lulus, tes + C05]
- **Lost-ack**: `SyncFailure.mayHaveCommitted`; tidak ada sukses palsu;
  form tidak menutup; `_saveError`; **createId stabil**; retry **tidak
  membuat transaksi kedua**; `RecordConcurrency.confirmsRetry`. [lulus, tes
  existing + C05]
- **Retry**: `_saving` di-reset; `_createId` dipertahankan; draft
  dipertahankan; app-level `_mutatingIds` dibersihkan di `_mutate.finally`;
  tidak ada write ganda. [lulus, tes existing]
- **UID switch**: `_mutate` `_sessionRevision`; `_clearUserData`;
  `SessionGate` menutup form UID lama; `_save` `sessionActive()` +
  `mounted`; **tidak ada write ganda**; **tidak ada feedback sesi lama**;
  `_confirmDiscard` `sessionRevision` check; `_saving` di-reset. [lulus, tes
  + C08]
- **stable createId**: `_createId ??= appState.generateId()`; tidak di-reset;
  id target edit `widget.existing!.id`; `AppState.updateTransaction` tolak id
  berubah. [lulus + C05/C08]
- **Tidak ada antrean offline baru**; tidak ada perubahan `AppState`/
  repository/Firestore; tidak ada klaim cancel RPC. [lulus]

## 5. Baseline vs hasil tes (evidence)

Lingkungan: Flutter 3.47.2 stable / Dart 3.13.2, Windows. `flutter test`;
`flutter analyze`; `dart format`.

| Tahap | Perintah | Hasil |
|---|---|---|
| Baseline (sebelum edit) | `flutter test` | **+434 -2**: 2 kegagalan **pra-eksisting** di `report_page_test.dart` (`paging on 320px...`, `partial cache disables export...`); sisanya lulus |
| Analyze baseline | `flutter analyze` | hanya `info` pra-eksisting `report_page_test.dart` `_iconBtnByTooltip` + 2 kegagalan tes tsb |
| Tes baru A1-09 saja | `flutter test test/transaction_dismissal_test.dart` | **+15 All tests passed!** (exit 0) |
| Pending/retry + dismissal | `flutter test test/offline_sync_widget_test.dart test/transaction_dismissal_test.dart test/record_conflict_widget_test.dart` | **+22 All tests passed!** (exit 0) |
| Suite offline/session/conflict + A1-09 | (offline_sync[_widget], session_*, record_conflict[_widget], transaction_sync/state/dismissal/date_picker) | **+93 All tests passed!** (exit 0) |
| Penuh (setelah edit) | `flutter test` | **+451 -2** (434 + 17; **sama 2 kegagalan pra-eksisting `report_page_test.dart`**; A1-09 tidak menambah kegagalan) |
| Statis | `flutter analyze lib/screens/transaction_page.dart test/transaction_dismissal_test.dart test/offline_sync_widget_test.dart` | **No issues found**; `flutter analyze` penuh hanya `info`/kegagalan pra-eksisting non-A1-09 |
| Format | `dart format` | bersih |
| **Verifikasi empiris** | scratch widget test (tidak dikomit): PopScope vs `Navigator.pop` vs `maybePop`; Back/close/tap luar/swipe; category/date-only dirty; pending; UID switch; **source SDK `navigator.dart` & `bottom_sheet.dart`** | temuan §2; scratch dihapus |

**Bukti reuse C05/C08**: tidak ada diff `app_state.dart` / `transaction_repository.dart` /
`session_gate.dart` / `transaction_sync_status.dart`; `offline_sync_*`,
`session_*`, `record_conflict*`, C05 `c05_offline_smoke`, C08 `c08_session_smoke`
tetap lulus. **Tidak ada antrean offline baru.** Log uji `%TEMP%`, tidak dikomit.

## 6. Batas bukti (evidence limits)

- **Tes memakai repository in-memory** (`MemoryTransactions`, `MemoryProfiles`,
  `SessionAuth`) di batas `TransactionRepository`, **bukan Firestore sungguhan**;
  tidak diuji Firebase live/emulator, rules Firestore, `runTransaction` nyata,
  atau konkurensi versi `RecordConcurrency` backend. C05/C08 punya smoke
  emulator terpisah yang **tidak dijalankan di sini**.
- **UID switch diuji** via `AppState.clearSession()` + sesi tetap mounted di
  harness (`SessionGate` tidak ikut memicu navigasi auth di test); di app
  nyata `SessionGate.pushNamedAndRemoveUntil` menutup form — jalur `mounted`
  + `sessionActive()` menjaga no-stale-feedback; **`repository.add` yang sudah
  in-flight tidak dapat dibatalkan** (tidak ada klaim cancel RPC); write untuk
  UID lama menarget koleksi UID itu sendiri; tidak ada write kedua/sesi baru
  (`attemptedIds` 1); klaim live-Firebase **tidak** diuji.
- **Swipe** diuji sebagai swipe-down pada handle bar (`fling`); SDK drag
  dinonaktifkan (`enableDrag:false`). Swipe pada area scrollable dalam sheet
  tidak dipaksa menjadi dismissal; cukup handle. **Back** diuji via
  `tester.binding.handlePopRoute()`, **tap luar** via `tapAt`, **close** via
  key; sistem Android back native tidak diuji di emulator.
- **Gesture real-device / pixel** tidak diuji; hanya widget/gesture test
  `flutter_test`. `_kSheetSwipeDismissVelocity=250` adalah pilihan desain,
  bukan syarat audit.
- **Lost-ack** bertumpu pada `SyncFailure.mayHaveCommitted` + retry id sama
  (`MemoryTransactions.failureAfterCommit`) + `confirmsRetry`; tidak ada
  replay offline otomatis (C05 `restart tidak membuat antrean...`).
- **Amount dirty** memakai perbandingan **teks** (format semantik tetap hanya
  dinilai saat simpan); **re-pilih kategori sama** tidak dirty; **paste/trim**
  hanya trim; `_checkDirty` tidak mem-`parseRupiah` sebagian.
- **2 kegagalan `report_page_test.dart` pra-eksisting** (baseline +434 -2)
  **tidak diselesaikan** di A1-09 (di luar scope; tidak disentuh); `info`
  `_iconBtnByTooltip` di file itu pra-eksisting.
- **A1-02/A1-04** tidak diubah; **handoff C** tidak dikerjakan.
- Pre-existing tak ter-commit **tidak disentuh**:
  `docs/a1-07-buktikan-unicode-quoting-dan-kebijakan-csv.md` (untracked);
  `backend/package-lock.json` terhapus & generated `GeneratedPluginRegistrant.*`
  / `generated_plugins.cmake` (dilaporkan pada baseline sebelumnya; tidak
  di-restore/di-stage).
- `frontend/lib/screens/privacy_page.dart`: pernah tersentuh sementara oleh
  `dart format lib`, **direstore via `git checkout`**; **tidak ada diff**.

## 7. BLOCKED

- **(a) Verifikasi literal vs dokumen audit A14** `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-frontend.md#a14`: sumber **tidak ada di repo**. Kriteria dinilai dari teks tugas A1-09. **BLOCKED**.
- **(b) Verifikasi vs "prompt pembuka file anggota 1"**: file prompt pembuka **tidak ada di repo**. Prompt pembuka tugas diterapkan sebagaimana diberikan (Flutter/Dart + Firebase tetap; commit manual; C05/C08 direuse; tidak ada antrean offline baru; scope awal; tidak ada tahap lanjut). Claim tambahan dari file itu: **BLOCKED**.
- **(c) Claim integrasi Firestore sungguhan / C05-C08 live emulator** diuji untuk A1-09: **BLOCKED** (hanya reuse + unit/widget; smoke emulator tidak dijalankan).
- **(d) Klaim pembatalan RPC**: tidak ada & tidak dijanjikan; pending hanya menampilkan `'permintaan belum dibatalkan.'`. 
- Jika input wajib (dokumen audit A14 / prompt pembuka file anggota 1) belum ada, claim terkait **BLOCKED**; selain itu kriteria lulus tugas **lulus**.

## 8. Dependency

- **Prasyarat lokal**: A1-02, A1-04 (terpenuhi). **Reuse**: C05, C08.
- **Tidak ada dependency baru**; `pubspec` tidak diubah; tidak ada antrean
  offline baru; tidak ada perubahan domain/repository/model.
- **Handoff C**: tidak ada; perubahan domain tambahan diserahkan ke handoff C.
- **Firebase**: tetap; tidak ada perubahan rules/struktur dokumen.
- Dokumen ini menutup audit **A14** untuk A1-09; audit A02/A1-04/A1-05...
  dipegang task lain.

## 9. Status

- **Status: SELESAI (implementasi + tes + dokumentasi).**
- **Berhenti setelah tahap ini. Tidak stage, tidak commit, tidak push, tidak
  deploy, tidak lanjut tahap berikutnya.**
- **Commit manual oleh user.** Pesan saran: `fix(transactions): lindungi
  draft kategori dan tanggal`.
- **Tidak ada diff kosong**: ada diff nyata; tidak membuat commit kosong.
- **Reservasi file bersama** (ditambah/diubah; jangan kerjakan paralel tanpa
  koordinasi):
  - `frontend/lib/screens/transaction_page.dart` (bersama task A1 lain)
  - `frontend/test/offline_sync_widget_test.dart` (diperluas; bersama C05)
  - `frontend/test/transaction_dismissal_test.dart` (baru; A1-09)
  - `docs/a1-09-lengkapi-dirty-state-dan-dismissal-transaksi.md` (baru)
  - Model/repository/`AppState`/`SessionGate` **tidak** diubah.
  - Pre-existing untracked `docs/a1-07-*.md`, `backend/package-lock.json`,
    generated plugin registrant **tidak** disentuh.

## 10. Handoff

- **Berhenti.** Tidak stage/commit/push/deploy; tidak lanjut tahap berikutnya.
- **Commit manual user** — perintah (dijalankan user, bukan saya); stage HANYA
  file A1-09; jangan ikutkan perubahan pra-eksisting/anggota lain:

  ```powershell
  git -C D:\flutter-workspace\simanja add `
    frontend/lib/screens/transaction_page.dart `
    frontend/test/offline_sync_widget_test.dart `
    frontend/test/transaction_dismissal_test.dart `
    docs/a1-09-lengkapi-dirty-state-dan-dismissal-transaksi.md
  git -C D:\flutter-workspace\simanja commit -m "fix(transactions): lindungi draft kategori dan tanggal"
  ```

- **Re-verifikasi pasca-commit**: `flutter test` (ekspektasi **+451**,
  sisa -2 pra-eksisting `report_page_test.dart`), `flutter analyze`,
  `dart format --set-exit-if-changed`; `flutter test
  test/offline_sync_widget_test.dart test/offline_sync_test.dart
  test/transaction_dismissal_test.dart test/transaction_date_picker_test.dart
  test/transaction_category_type_preservation_test.dart` (C05/C08 + A1-02/A1-04).
- **Rollback**: `git restore frontend/lib/screens/transaction_page.dart
  frontend/test/offline_sync_widget_test.dart`; hapus
  `frontend/test/transaction_dismissal_test.dart` & doc ini.
