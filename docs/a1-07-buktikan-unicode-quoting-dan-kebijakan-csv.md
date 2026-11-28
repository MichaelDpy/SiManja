# A1-07 — Buktikan Unicode, quoting dan kebijakan CSV

- **Task**: A1-07 SIMANJA; menutup audit **A07**.
- **Tanggal**: 2026-11-27.
- **Stack**: Flutter/Dart + Firebase (tidak berubah). **Commit manual oleh user**;
  tidak ada stage/commit/push/deploy pada tahap ini. Berhenti setelah tahap ini.
- **Pesan commit saran**: `test(csv): verifikasi unicode dan keamanan ekspor`.
- **Scope awal** (dipatuhi): `frontend/lib/core/csv_exporter.dart`; tes
  serializer / `report_export` terkait. Tidak ada perubahan domain; tidak ada
  rewrite `SessionExportStore`; tidak mengganti `codeUnits` lagi; **hanya
  pengerjaan A1-07**, tidak melanjutkan A1-08/A1-09.

> Catatan referensi: dokumen audit sumber
> `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-frontend.md#a07`
> dan "prompt pembuka file anggota 1" **tidak ada di dalam repo** ini (dicari di
> `docs/`, root, dan seluruh worktree; tidak ditemukan; bukan di git branch/stash
> yang tersedia). Claim yang bergantung pada isi dokumen audit A07 / file
> anggota 1 tersebut ditandai **BLOCKED** di bawah. Kriteria lulus diuji langsung,
> tidak disimpulkan dari dokumen itu. Prompt pembuka yang diberikan diterapkan
> sebagaimana ditulis: **Flutter/Dart + Firebase tetap, commit manual oleh user**;
> kerjakan hanya A1-07; tidak stage/commit/push/deploy; tidak lanjut tahap
> berikutnya; berhenti setelah tahap ini; tidak membuat commit kosong.

---

## 1. Path & simbol aktual (ditemukan sebelum edit)

- `frontend/lib/core/csv_exporter.dart`
  - `abstract final class CsvExporter`
    - `static Future<CsvExportResult> export({required List<TransactionModel>
      transactions, required String periodLabel, String search = '',
      bool Function()? isCurrent, SessionExportLease? lease})` — **tidak diubah**
      pada A1-07 (rasa share hasil `ShareResult` & race C07/C08 adalah **A1-08**;
      tidak disentuh).
    - `static int _exportSequence`, `_exportSequence++`.
    - `static List<int> encode(List<TransactionModel> transactions,
      String periodLabel, {String search = ''})` — serializer.
    - `_quoteField(String raw)`, `_metadataLine(String text)`,
      `_isoDate(DateTime d)`.
    - **UTF-8 + BOM**: `const bom = [0xEF, 0xBB, 0xBF]; return [...bom,
      ...utf8.encode(buf.toString())];` (**sudah ada**; komentar A07). `dart:convert`
      `utf8.encode`, **bukan `codeUnits`** (UTF-16). **Tidak mengganti `codeUnits`
      lagi.**
    - `_isoDate` memakai `intl` `DateFormat('yyyy-MM-dd')`.
    - Kolom: `tanggal_iso,kategori,keterangan,jenis,nominal_rupiah`;
      `jenis` = `pemasukan`/`pengeluaran` (`tx.isIncome`);
      `nominal_rupiah` = `Rupiah.digits(tx.amount)`.
    - **Ditambahkan (A1-07)**:
      - `static const List<int> utf8Bom = <int>[0xEF, 0xBB, 0xBF];`
      - `static const String recordSeparator = '\n';`
      - `static String decodeStrict(List<int> bytes)` — UTF-8 ketat
        (`utf8.decode(..., allowMalformed: false)`), melempar `FormatException`
        untuk byte malformed / sequence terpotong, **melepas satu BOM UTF-8 di
        awal**; tidak menormalkan newline.
      - `static List<List<String>> parseCsv(String input)` — **parser CSV
        independen** (RFC-4180-style), tidak memakai/copy serializer; menangani
        field berkutip `"..."`, kutip ganda `""`, koma & newline di dalam field
        kutipan, separator `\n`/`\r\n`/`\r`, kolom kosong, field kutipan kosong,
        trailing comma, separator akhir (tidak menambah record kosong),
        `\uFEFF` di awal; melempar `FormatException` bila kutipan tidak ditutup
        atau ada karakter tak terduga setelah kutipan penutup; newline di dalam
        field kutipan dinormalisasi `\r\n`→`\n`, `\r`→`\n`.
  - `CsvExportResult` (`_CsvExportStatus` `success/empty/cancelled/stale/failure`;
    `isSuccess/isEmpty/isCancelled/isStale/isFailure`, `errorMessage`) — **tidak
    diubah**.
  - `Rupiah.digits` (`frontend/lib/core/rupiah.dart`): integer rupiah desimal;
    batas `Rupiah.maxRecord = 9007199254740991`. **Tidak diubah.**
  - `TransactionModel` (`frontend/lib/models/transaction_model.dart`): `amount`
    double integer **positif** finite, `category`/`description` string bebas,
    `isIncome`, `date`. **Tidak diubah.**
  - `SessionExportStore` / `SessionExportLease`
    (`frontend/lib/core/session_artifacts.dart`) — **dibaca; tidak diubah**
    (C07/C08 sudah ada; snapshot unik per export; `isCurrent`; `discard`;
    `retire`; `_exportSequence` + `microsecondsSinceEpoch`). Reuse `lease` C08.
- `frontend/test/report_export_test.dart` — tes `CsvExporter.encode` +
  `CsvExporter.export`, MethodChannel `plugins.flutter.io/path_provider` &
  `dev.fluttercommunity.plus/share`, `SessionExportStore.useForTesting`, fixture
  `reportFixture` (`frontend/test/support/memory_history.dart`). **Tidak
  diubah.**
- **Tes serializer terkait**: tidak ada file serializer CSV terpisah; serializer
  = `CsvExporter.encode`. (Tes `_quoteField` tidak ada di baseline.)

### Reservasi file bersama

- **Diubah**: `frontend/lib/core/csv_exporter.dart` (hunk di bawah),
  `frontend/test/csv_unicode_quoting_test.dart` (**baru**),
  `docs/a1-07-buktikan-unicode-quoting-dan-kebijakan-csv.md` (**baru**, ini).
- **Read-only / tidak diubah**: `frontend/lib/core/session_artifacts.dart`,
  `frontend/lib/core/rupiah.dart`, `frontend/lib/models/transaction_model.dart`,
  `frontend/test/report_export_test.dart`, `frontend/test/session_artifacts_test.dart`,
  `frontend/test/support/memory_history.dart`, `frontend/lib/screens/data_table_page.dart`
  (jalur pemanggil `CsvExporter.export`, A1-08), `frontend/lib/firebase_options.dart`,
  Firestore rules, `pubspec.yaml`/`pubspec.lock`.
- **Jangan kerjakan paralel tanpa koordinasi** pada `csv_exporter.dart` (juga
  dipakai A1-08 `report_export_test.dart` & C07/C08 lease) & `report_export_test.dart`.
- **Pra-eksisting tak disentuh**: `docs/a1-03-selaraskan-batas-validasi-editor-dan-
  domain.md` sudah **staged** sebelum tugas ini; tidak diubah/unstage. Perubahan
  anggota lain/baseline lain tidak disentuh.

---

## 2. Kebijakan CSV (ditetapkan; tanpa mengubah domain)

**UTF-8 + BOM.** Output `CsvExporter.encode` = UTF-8 **BOM** (`EF BB BF`,
`CsvExporter.utf8Bom`) + `utf8.encode(...)`. Encoding memakai `utf8.encode`,
**bukan `codeUnits`**. Unicode **tidak rusak**: `Café`, `中文`, emoji (Café/中文/
😀/🎉🚀), koma, kutip, newline, awalan formula tidak merusak teks; em-dash `—`
tetap. **Tidak mengubah domain** (`TransactionModel`, repository, `Rupiah`,
`CsvExportResult`, `SessionExportStore`, skema Firestore) — hanya lapisan
serialisasi + parser.

**Quoting.** **Semua** field (termasuk kolom teks, header, `nominal`, field
kosong) dibungkus `"..."`; kutip `"` di dalam di-escape jadi `""`. Koma `,`
di dalam field kutipan bukan pemisah. Teks tidak pernah menyisipkan record
tambahan.

**Normalisasi newline.**
- Separator record output **selalu `\n` (LF)**, satu `\n` di akhir tiap baris,
  tidak ada baris kosong tambahan, output diakhiri satu `\n`; **tidak ada `\r`**.
  `CsvExporter.recordSeparator == '\n'`.
- Newline **di dalam nilai field** (`\n`, `\r\n`, `\r`) dinormalisasi menjadi
  **satu spasi**, jadi teks tidak menyisipkan record baris tambahan. (Kebijakan
  yang sudah ada `_quoteField`; **tidak** dipertahankan sebagai newline berkutip.)
- Newline pada **baris komentar metadata** (`#...`, `# Periode`, `# Pencarian`,
  `# Diekspor`, `# Jumlah baris`) dinormalisasi ke spasi (`_metadataLine`;
  `# Pencarian` juga). `periodLabel`/`search` tidak menyisipkan record.
- Parser independen `parseCsv` menerima separator `\n`/`\r\n`/`\r`; newline di
  dalam field kutipan dinormalisasi ke `\n`.
- `#` komentar metadata tetap (baris tunggal-kolom yang diawali `#`, bukan
  formula; `#` di kolom dan `# Jumlah baris: N`). Scope pencarian/periode hanya
  metadata; **tidak** mengubah baris data. `# Jumlah baris` = jumlah data rows.

**Guard formula (CSV injection).** Field teks yang karakter **pertama** (`s[0]`)
adalah salah satu `=`, `+`, `-`, `@`, `|`, `%` (`'=+-@|%'`) diawali **satu
spasi**. `_quoteField` menerapkannya **tanpa mengubah domain** & tanpa mengubah
nilai lain; `nominal_rupiah` (digit saja) tidak kena. **Tidak** menjanjikan
proteksi eksekusi spreadsheet di luar ini. (Kebijakan sudah ada; ditetapkan +
diuji.) Lihat batas bukti soal target spreadsheet sungguhan.

**Nominal exact.** `nominal_rupiah` = string integer desimal persis
`Rupiah.digits(tx.amount)` (positif, finite, integer, ≤ `Rupiah.maxRecord` =
`9007199254740991`); **tidak** kena guard formula/pembulatan; `BigInt.parse`
round-trip. `# Jumlah baris` = N.

**Strict decode.** `decodeStrict` `allowMalformed:false` (tidak ada U+FFFD),
melempar `FormatException`; melepas satu BOM UTF-8 awal. Round-trip
`decodeStrict(encode(...))` + `parseCsv` → header/kolom/baris benar.

---

## 3. Perubahan yang dilakukan (exact files & hunks)

**Hanya satu file kode diubah + satu file test baru + dokumen ini.**

### 3.1 `frontend/lib/core/csv_exporter.dart`

(relatif baseline `HEAD=7728f5a`; `git diff` penuh direkam pada percakapan;
verifikasi `git diff` sebelum commit.)

- **Doc-comment header `CsvExporter`** (hunk `@@ -13,9 +13,24 @@`): aturan keamanan
  diperjelas (koma/kutip `""`, guard `=,+,-,@,|,%`, UTF-8 BOM, `utf8.encode`
  bukan `codeUnits`); bagian baru **Normalisasi newline (A1-07, tanpa mengubah
  domain)** & **Decode `decodeStrict`**.
- **`encode` komentar** (hunk `@@ -116,12 +131,161 @@`, baris ~131-134):
  `A07` → `A07/A1-07`, keterangan `utf8.encode` bukan `codeUnits`. **Body
  serializer tidak diubah** (BOM + `utf8.encode`, `writeln` LF, `_quoteField`).
- **Ditambahkan** setelah `encode`, sebelum `_isoDate` (hunk `@@ ... +161`,
  baris ~136-291):
  - `static const List<int> utf8Bom`, `static const String recordSeparator`.
  - `static String decodeStrict(List<int> bytes)`.
  - `static List<List<String>> parseCsv(String input)`.
- **Tidak diubah**: `export`, `CsvExportResult`, `_quoteField`, `_metadataLine`,
  `_isoDate`, `Rupiah.digits`, `TransactionModel`, `SessionExportStore`.
- `dart analyze` bersih pada file ini.

### 3.2 `frontend/test/csv_unicode_quoting_test.dart` (**baru**, 18 tes)

Expected ditulis sebagai **literal diketahui**; **tidak** `expect contains`
sebagai satu-satunya bukti; **tidak** menyalip serializer menjadi expected;
parsing round-trip memakai **parser independen** `CsvExporter.parseCsv`, dan
ada tes **input hand-crafted CSV** (bukan output serializer) untuk membuktikan
independensi. Kelompok:

- **encode→decodeStrict→parseCsv round-trip**: BOM `EF BB BF`; strict UTF-8;
  tidak ada U+FFFD; `é`=`C3 A9`; header `tanggal_iso,kategori,keterangan,jenis,
  nominal_rupiah`; `2026-11-27`; `pemasukan`/`pengeluaran`; **Café / 中文 /
  Emoji 😀 / 🎉🚀**; koma; kutip `"`; newline; **scope** N baris persis tidak
  ada record tambahan; `# Jumlah baris`; `# Periode`/`# Pencarian`; **nominal
  exact** `12345`,`67890`,`9007199254740991`,`1000`,`2000`,`3000`,`7`,`9`,`42`,
  `100`,`200`,`9007199254740991`,`1234567`,`BigInt.parse`; `# Pencarian`
  `needle =1+1`. **Kolom koma/kutip/newline/Café/中文/emoji tidak menyisipkan
  record.** **Scope pencarian tidak mengubah baris.**
- **Normalisasi newline**: separator LF; satu trailing LF; tidak ada `\r`/baris
  kosong; inner `\n`/`\r\n`/`\r`→satu spasi; tidak ada record tambahan; metadata
  newline→spasi; parser inner→LF; parser separator `\n`/`\r\n`/`\r`.
- **Guard formula** `= + - @ | %`: kategori/keterangan diawali spasi; `=1+1`→
  ` =1+1`; `=SUM(A1:A2)`→` =SUM(A1:A2)`; `@SUM(1,2)`→` @SUM(1,2)`; inner kutip/
  koma/newline tetap; nominal exact tidak tersentuh; tidak mengubah domain.
- **Strict UTF-8**: Café/中文/emoji round-trip ketat; BOM dilepas; malformed
  (`0xFF`,`0xFE`,`0x80`,`0x41 0x80`,overlong `0xC0 0x80`,terpotong `0xC3`,
  `0xE4 0xB8`,`0xF0 0x9F 0x98`,>U+10FFFF `0xF4 0x90 0x80 0x80`,surrogate
  `0xED 0xA0 0x80`)→`FormatException`.
- **Parser independen**: hand-crafted CRLF/CR/LF; `""`; kolom kosong; trailing
  comma; separator akhir; inner koma/kutip/newline; Unicode; kutipan tidak
  ditutup→`FormatException`; karakter setelah kutipan penutup→`FormatException`.
- Tidak menghapus/memodifikasi tes existing; tes `report_export` C07/C08 tetap.

### 3.3 Dokumen

`docs/a1-07-buktikan-unicode-quoting-dan-kebijakan-csv.md` (ini).

---

## 4. Kriteria lulus (cara diverifikasi)

- **Header/kolom/baris hasil parse benar**: `parseCsv(decodeStrict(encode(...)))`
  → header `tanggal_iso,kategori,keterangan,jenis,nominal_rupiah`; tiap baris 5
  kolom; jumlah baris data == N; `tanggal_iso` `YYYY-MM-DD`; `jenis`
  `pemasukan`/`pengeluaran`. **[lulus]**
- **Unicode tidak rusak & nominal exact**: Café/中文/emoji persis; koma/kutip
  dipertahankan; nominal string integer persis (incl. `9007199254740991`);
  `BigInt.parse`. **[lulus]**
- **Teks tidak menyisipkan record tambahan**: inner newline→spasi; metadata
  newline→spasi; jumlah baris stabil; separator LF tunggal. **[lulus]**
- **UTF-8 + BOM sudah ada**: `EF BB BF` + `utf8.encode`, **tidak** `codeUnits`.
  **[lulus; tidak mengganti codeUnits lagi]**
- **Strict decode**: `allowMalformed:false`, `FormatException`, BOM dilepas.
  **[lulus]**
- **Parser CSV independen**: bukan copy serializer; input hand-crafted; round-
  trip + scope + nominal (bukan hanya `contains`). **[lulus]**
- **Normalisasi newline & guard formula tanpa mengubah domain**: LF separator;
  inner→spasi; `=,+,-,@,|,%`→leading space; nominal/domain tidak berubah.
  **[lulus]**
- **Verifikasi round-trip/parse + scope/nominal**: `encode→decodeStrict→parseCsv`;
  scope `search`/`# Jumlah baris`; nominal exact. **[lulus]**
- **Bukti guard/interoperabilitas dibatasi pada target yang benar-benar diuji**:
  lihat Batas bukti. **Tidak ada klaim terhadap Excel/LibreOffice sungguhan.**
- **Prasyarat lokal A1-06**: kode A1-06 ada (`frontend/lib/screens/report_page.dart`
  navigasi periode maju/`A1-06` tes di `report_page_test.dart`, commit
  `7728f5a`); **tidak ada `docs/a1-06-*`** & tidak ada catatan handoff A1-06 di
  repo → klaim "A1-06 ditutup" **BLOCKED**, bukan disimpulkan; tidak diubah.
- **Gate**: tidak mengubah domain; tidak rewrite `SessionExportStore`; tidak
  mengganti `codeUnits`; C07/C08 direuse (tidak disentuh); tanpa spreadsheet
  nyata **gap eksternal dicatat**; hanya A1-07; tidak stage/commit/push/deploy;
  tidak lanjut A1-08/A1-09; tidak membuat commit kosong.

---

## 5. Dependency

- **Flutter/Dart + Firebase tetap.** Flutter 3.47.2 stable / Dart 3.13.2, Windows.
- `dart:convert` `utf8` (SDK), `dart:core` `FormatException`; `intl`
  `DateFormat` (`intl: ^0.20.3`, sudah ada); `Rupiah`. **Tidak ada dependency
  baru**; `pubspec.yaml`/`pubspec.lock` tidak diubah; **tidak ada paket CSV
  eksternal** (parser independen ditulis sendiri); `share_plus` tidak disentuh
  (A1-08); `SessionExportStore` tidak disentuh.
- **Firebase**: tidak ada perubahan rules/struktur dokumen; tidak diuji live.

---

## 6. Baseline vs hasil tes (evidence)

Lingkungan: Flutter 3.47.2 stable / Dart 3.13.2, Windows; output konsol
PowerShell `cp1252` hanya memengaruhi *rendering* konsol, bukan byte CSV
(diverifikasi via parser ketat + cross-check Python UTF-8).

| Tahap | Perintah | Hasil |
|---|---|---|
| Baseline `report_export` (sebelum edit) | `flutter test test/report_export_test.dart` | **+6 All tests passed!** (exit 0) |
| Suite CSV baru | `flutter test test/csv_unicode_quoting_test.dart` | **+18 All tests passed!** (exit 0) |
| `report_export` + CSV baru | `flutter test test/report_export_test.dart test/csv_unicode_quoting_test.dart` | **+24 All tests passed!** (exit 0) |
| `report_export` + CSV + `session_artifacts` | `flutter test test/report_export_test.dart test/csv_unicode_quoting_test.dart test/session_artifacts_test.dart` | **+30 All tests passed!** (exit 0) |
| Statis file | `dart analyze lib/core/csv_exporter.dart` | **No issues found!** |
| Statis seluruh | `flutter analyze` | **1 info pra-eksisting** (`no_leading_underscores_for_local_identifiers` `test/report_page_test.dart:323`, bukan file ini; tidak diubah); exit 1 karena info |
| Penuh `flutter test` | `flutter test` | **+431, -2**: 2 **kegagalan pra-eksisting** di `report_page_test.dart` (lihat di bawah); semua tes A1-07 + C07/C08 + existing lainnya lulus |

**Verifikasi independen tambahan (tidak hanya tes Dart):** output sampel
(`Café, 中文 😀`, kutip/koma/newline→spasi, `9007199254740991`, `=1+1`→` =1+1`,
`@SUM(1,2)`→` @SUM(1,2)`, scope `Café\r\n=1+1`, `# Jumlah baris: 2`, UTF-8 BOM,
em-dash `—`) diparse dengan **Python 3.9 `csv` + `utf-8-sig` `errors='strict'`**
(parser independen, **bukan** spreadsheet): header benar, 2 data rows, nominal
exact, Unicode utuh, guard formula, no injection. Contoh sementara tidak
dikomit.

**Kegagalan pra-eksisting (BUKAN A1-07; dibuktikan pada baseline tanpa perubahan
saya, `git stash` `csv_exporter.dart` lalu `flutter test test/report_page_test.dart`):**
`test/report_page_test.dart` `paging on 320px preserves full summary and search
on hidden pages` (`'1–50 dari 137 transaksi'` tidak ditemukan) &
`partial cache disables export; server/realtime/reload restores full selection`
(`'1–50 dari 138 transaksi'` tidak ditemukan). File **tidak diubah**; **tidak**
diklaim lulus. Tidak disentuh di A1-07. `flutter analyze` info `report_page_test`
pra-eksisting. Tidak ada klaim `flutter test` penuh hijau.

Log uji sementara, tidak dikomit.

---

## 7. Batas bukti (evidence limits) & BLOCKED

- **Tanpa spreadsheet nyata.** Tidak ada Excel/LibreOffice/Google Sheets/`ssconvert`
  di lingkungan; **tidak ada smoke share Android** (A1-08) & tidak ada uji
  "Excel membuka BOM dengan benar" sungguhan. Kebijakan BOM/UTF-8/guard formula
  diuji **hanya** via `CsvExporter.parseCsv`, `decodeStrict`, dan **Python `csv`
  independen**. **Gap eksternal dicatat**; tidak mengklaim interop terhadap
  target spreadsheet yang benar-benar tidak diuji. **"Bukti guard/interoperabilitas
  dibatasi pada target yang benar-benar diuji."** Uji spreadsheet target bila
  tersedia **belum dilakukan**.
- **Formula guard** hanya menambah satu spasi pada `=,+,-,@,|,%` di karakter
  pertama field teks; **tidak** mengklaim pencegahan eksekusi spreadsheet di
  luar apa yang diuji; inner newline→spasi tetap; nominal tidak kena.
- **Newline di dalam field tidak dipertahankan**; dinormalisasi ke satu spasi
  (kebijakan sudah ada, ditetapkan & diuji). Parser menormalkan separator &
  inner newline hanya untuk inputnya.
- **Round-trip bukan identitas mentah** karena normalisasi newline + guard
  formula + strict decode; Unicode & nominal tetap persis. Teks `Café`/`中文`/
  emoji/koma/kutip tidak rusak; kutip `"` di dalam di-escape `""`.
- **`decodeStrict`** menolak malformed UTF-8; **tidak** menormalkan newline
  pada hasil decode; `parseCsv` melakukan normalisasi newline. `FormatException`
  pada kutipan tidak ditutup / karakter setelah kutipan penutup.
- **C07/C08 share/race** adalah **A1-08**; `export`, `CsvExportResult`,
  `SessionExportStore`, share sheet, `ShareResultStatus`, klaim "copy penerima
  tidak dapat dicabut", dispose/A→B/ABA/dua export/I-O lambat **tidak** dikerjakan
  & **tidak** diklaim. `report_export_test.dart` C07/C08 existing tetap lulus.
- **Domain tidak diubah**; `TransactionModel`, `Rupiah`, repository, Firestore
  tidak disentuh. Nominal positif integer ≤ maxRecord (domain); `Rupiah.digits`
  tidak diperluas.
- **Kriteria dari dokumen audit A07** tidak dapat dibandingkan baris-per-baris:
  dokumen audit sumber `../audit-anggota-1-dan-2-2026-11-27/01-audit-anggota-1-
  frontend.md#a07` **tidak ada di repo**; kriteria lulus dinilai dari teks tugas
  A1-07. Claim yang memerlukan isi audit A07 / "prompt pembuka file anggota 1":
  **BLOCKED**.
- **Prasyarat lokal A1-06**: implementasi ada di kode & tes `A1-06`, tetapi
  **tidak ada `docs/a1-06-*`**; klaim bahwa prasyarat A1-06 "ditutup/dicatat"
  **BLOCKED**; tidak diubah.
- **"Terapkan prompt pembuka file anggota 1 ini"**: file anggota 1 tidak ditemukan
  di repo; pembuka yang diberikan pada prompt ini diterapkan (stack tetap,
  commit manual, scope, berhenti, tidak commit). Claim tambahan dari file itu:
  **BLOCKED**.
- **Input wajib tidak ada** → claim terkait **BLOCKED**; **tidak ada diff kosong**
  (ada diff nyata; tidak membuat commit kosong).
- **Reservasi file bersama** (di atas); tidak membuat model duplikat; tidak
  membuat file anggota/tim baru selain doc `docs/a1-07-...`.
- **Firebase live/Firestore** tidak diuji; tidak ada klaim Firebase baru.
- **Pra-eksisting tak disentuh**: `docs/a1-03-...` sudah staged; perubahan
  baseline/lain bukan A1-07; 2 kegagalan `report_page_test` pra-eksisting; 1
  info analyze pra-eksisting.

---

## 8. Status

- **Status: SELESAI** untuk kriteria A1-07 yang dapat dibuktikan lokal
  (Unicode+BOM, strict decode, quoting, parser independen, normalisasi newline,
  guard formula, round-trip + scope + nominal; baseline test + hasil test;
  `dart analyze`/`flutter analyze` sesuai catatan). **Hanya A1-07**; tidak
  melanjutkan tahap berikutnya; **tidak stage/commit/push/deploy**; **tidak ada
  diff kosong**.
- **BLOCKED**: (a) klaim literal vs dokumen audit **A07** & **prompt pembuka
  file anggota 1** (sumber tidak ada di repo); (b) klaim **prasyarat A1-06
  ditutup/dicatat** (kode/tes ada, doc `docs/a1-06-*` tidak ada); (c) klaim
  **interop terhadap spreadsheet sungguhan / uji spreadsheet target** (tidak
  tersedia; hanya parser independen Dart + Python `csv`); (d) klaim **share
  result / race C07/C08** (A1-08); (e) klaim **Firebase/Firestore live**;
  (f) klaim `flutter test` penuh hijau (2 kegagalan pra-eksisting di
  `report_page_test`, di luar A1-07).
- **Jika input wajib belum ada, claim terkait BLOCKED.** **Jika tanpa diff,
  jangan commit kosong** — di sini ada diff nyata.

## 9. Handoff

- **Berhenti setelah tahap ini.** **Tidak stage, tidak commit, tidak push,
  tidak deploy, tidak lanjut tahap berikutnya. Commit manual oleh user.**
  Pesan saran: `test(csv): verifikasi unicode dan keamanan ekspor`.
- **Stage HANYA file A1-07** saat user memilih commit manual:
  `frontend/lib/core/csv_exporter.dart`, `frontend/test/csv_unicode_quoting_
  test.dart`, `docs/a1-07-buktikan-unicode-quoting-dan-kebijakan-csv.md`.
  Jangan ikutkan `docs/a1-03-...` (sudah staged pra-eksisting) atau perubahan
  lain. **Tidak ada commit kosong.**
- **Perintah commit (dijalankan USER, bukan saya)** contoh:
  `git add frontend/lib/core/csv_exporter.dart frontend/test/csv_unicode_
  quoting_test.dart docs/a1-07-buktikan-unicode-quoting-dan-kebijakan-csv.md`
  lalu `git commit -m "test(csv): verifikasi unicode dan keamanan ekspor"`.
- **Re-verifikasi pasca-commit**: `flutter test test/csv_unicode_quoting_test.dart
  test/report_export_test.dart test/session_artifacts_test.dart` (ekspektasi
  +24/+30); `flutter test test/report_export_test.dart test/csv_unicode_
  quoting_test.dart` +24; `dart analyze lib/core/csv_exporter.dart` bersih;
  catat batas bukti; **2 kegagalan `report_page_test` pra-eksisting** bukan
  A1-07; **gap eksternal spreadsheet**; **BLOCKED** di §7.
- **A1-08** (`ShareResult`, dismissed/failure/unknown, copy tidak dicabut,
  dispose/A→B/ABA/dua export/I-O lambat/file unik, lease C08 reuse, smoke share
  Android terpisah dari MethodChannel fake) **tidak dikerjakan**; **A1-09** tidak
  dikerjakan.
- **Rollback**: `git restore frontend/lib/core/csv_exporter.dart`; hapus
  `frontend/test/csv_unicode_quoting_test.dart` & `docs/a1-07-...md`.
