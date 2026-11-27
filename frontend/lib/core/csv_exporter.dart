import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'rupiah.dart';
import 'session_artifacts.dart';
import '../models/transaction_model.dart';

/// Utilitas ekspor transaksi ke file CSV.
///
/// Format kolom:
///   tanggal_iso, kategori, keterangan, jenis, nominal_rupiah
///
/// Aturan keamanan:
/// - Semua field teks di-quote dan koma/kutip di-escape (kutip ganda `""`).
/// - Field yang diawali karakter formula (=, +, -, @, |, %) diawali spasi
///   (CSV injection guard).
/// - Encoding UTF-8 dengan BOM agar Excel membuka dengan benar.
///   Encoding ditulis dengan `utf8.encode`, BUKAN `codeUnits` (UTF-16).
///
/// Normalisasi newline (A1-07, tanpa mengubah domain):
/// - Separator record output selalu `\n` (LF), satu `\n` di akhir tiap baris,
///   tidak ada baris kosong tambahan; output diakhiri satu `\n`.
/// - Newline di DALAM nilai field (`\n`, `\r\n`, `\r`) dinormalisasi menjadi
///   satu spasi, sehingga teks tidak pernah menyisipkan record tambahan.
/// - Newline pada baris komentar metadata (#...) juga dinormalisasi ke spasi.
/// - Parser independen [parseCsv] menerima separator `\n`, `\r\n`, `\r`,
///   dan menormalisasi newline di dalam field kutipan menjadi `\n`.
///
/// Decode: [decodeStrict] melakukan UTF-8 decode KETAT
/// (`allowMalformed: false`), melempar [FormatException] untuk byte malformed
/// atau sequence terpotong, serta melepas satu BOM UTF-8 di awal.
///
/// [CsvExportResult] membedakan berhasil, dibatalkan pengguna, dan gagal.
abstract final class CsvExporter {
  /// Ekspor [transactions] ke file CSV lalu buka share sheet.
  ///
  /// [periodLabel] dipakai di nama file dan baris pertama komentar.
  /// Kembalikan [CsvExportResult].
  static Future<CsvExportResult> export({
    required List<TransactionModel> transactions,
    required String periodLabel,
    String search = '',
    bool Function()? isCurrent,
    SessionExportLease? lease,
  }) async {
    final files = lease ?? SessionExportStore.instance.newLease();
    bool current() => files.isActive && (isCurrent?.call() ?? true);
    if (!current()) return const CsvExportResult.stale();
    if (transactions.isEmpty) {
      return const CsvExportResult.empty();
    }

    try {
      final csvBytes = encode(transactions, periodLabel, search: search);

      final safePeriod = periodLabel
          .replaceAll(RegExp(r'[^\w\-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final fileName =
          'simanja_transaksi_${safePeriod}_${DateTime.now().microsecondsSinceEpoch}_${_exportSequence++}.csv';
      final file = await files.write(csvBytes, fileName, isCurrent: current);
      if (file == null) return const CsvExportResult.stale();
      if (!current()) {
        await files.discard(file);
        return const CsvExportResult.stale();
      }

      // share_plus v10 masih menggunakan API static Share.shareXFiles
      final result = await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'Data Transaksi SIMANJA — $periodLabel');
      if (!current()) return const CsvExportResult.stale();

      if (result.status == ShareResultStatus.dismissed) {
        return const CsvExportResult.cancelled();
      }
      return const CsvExportResult.success();
    } catch (_) {
      if (!current()) return const CsvExportResult.stale();
      return const CsvExportResult.failure(
        'Berkas CSV belum dapat dibagikan. Coba lagi.',
      );
    }
  }

  // ── CSV builder ───────────────────────────────────────────────────────

  static int _exportSequence = 0;

  /// Serializes the transaction snapshot used by sharing and regression tests.
  static List<int> encode(
    List<TransactionModel> transactions,
    String periodLabel, {
    String search = '',
  }) {
    final buf = StringBuffer();

    // Header baris komentar (diawali # → bukan formula)
    buf.writeln('# SIMANJA — Ekspor Data Transaksi');
    buf.writeln('# Periode: ${_metadataLine(periodLabel)}');
    if (search.trim().isNotEmpty) {
      buf.writeln('# Pencarian: ${_metadataLine(search)}');
    }
    buf.writeln('# Diekspor: ${_isoDate(DateTime.now())}');
    buf.writeln('# Jumlah baris: ${transactions.length}');
    buf.writeln('#');

    // Header kolom
    buf.writeln(
      [
        'tanggal_iso',
        'kategori',
        'keterangan',
        'jenis',
        'nominal_rupiah',
      ].map(_quoteField).join(','),
    );

    for (final tx in transactions) {
      buf.writeln(
        [
          _isoDate(tx.date),
          tx.category,
          tx.description,
          tx.isIncome ? 'pemasukan' : 'pengeluaran',
          // Nominal sebagai integer — tidak ambigu, mudah diolah spreadsheet
          Rupiah.digits(tx.amount),
        ].map(_quoteField).join(','),
      );
    }

    // A07/A1-07: UTF-8 BOM agar Excel Windows membuka dengan encoding benar.
    // Gunakan utf8.encode, bukan codeUnits yang memberi UTF-16 code units.
    const bom = [0xEF, 0xBB, 0xBF];
    return [...bom, ...utf8.encode(buf.toString())];
  }

  // ── Strict UTF-8 decode + parser CSV independen (A1-07) ────────────────

  /// BOM UTF-8 (EF BB BF) yang ditulis di awal output [encode].
  static const List<int> utf8Bom = <int>[0xEF, 0xBB, 0xBF];

  /// Separator record yang ditulis serializer: LF.
  static const String recordSeparator = '\n';

  /// UTF-8 decode KETAT.
  ///
  /// - `allowMalformed: false`: byte malformed / sequence terpotong melempar
  ///   [FormatException]; tidak ada karakter pengganti (U+FFFD).
  /// - Menghapus satu BOM UTF-8 di awal bila ada.
  /// - TIDAK melakukan normalisasi newline; pakai [parseCsv] untuk itu.
  ///
  /// Encoding output [encode] adalah UTF-8 + BOM (`utf8.encode`, bukan
  /// `codeUnits`); round-trip `decodeStrict(encode(...))` menghasilkan teks
  /// yang sama seperti yang diserialisasi sebelum BOM.
  static String decodeStrict(List<int> bytes) {
    var offset = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      offset = 3;
    }
    final body = offset == 0 ? bytes : bytes.sublist(offset);
    return utf8.decode(body, allowMalformed: false);
  }

  /// Parser CSV RFC-4180-style, INDEPENDEN dari serializer [encode].
  ///
  /// Menghasilkan daftar record; tiap record daftar kolom string.
  /// - Field boleh dikutip `"..."`; kutip di dalam field kutipan di-escape
  ///   menjadi `""`.
  /// - Koma dan newline di dalam field kutipan diperlakukan sebagai data,
  ///   bukan pemisah.
  /// - Separator record `\n`, `\r\n`, `\r` diterima; separator di akhir tidak
  ///   menambah record kosong.
  /// - Newline di dalam field kutipan dinormalisasi: `\r\n` -> `\n`, `\r` ->
  ///   `\n`.
  /// - Satu BOM UTF-8 di awal input dilepas.
  /// - Field tidak dikutip dibaca apa adanya; kolom kosong -> `''`.
  ///
  /// Melempar [FormatException] bila kutipan tidak ditutup atau ada karakter
  /// tak terduga setelah kutipan penutup. Tidak pernah menambah record
  /// tersembunyi dari teks.
  static List<List<String>> parseCsv(String input) {
    var text = input;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final n = text.length;
    if (n == 0) return const <List<String>>[];

    final records = <List<String>>[];
    var record = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var atFieldStart = true; // belum ada konten/kutip di kolom ini
    var afterClosingQuote = false; // hanya pemisah yang boleh mengikuti

    void finishField() {
      record.add(field.toString());
      field.clear();
      atFieldStart = true;
      afterClosingQuote = false;
    }

    void finishRecord() {
      finishField();
      records.add(record);
      record = <String>[];
    }

    var i = 0;
    while (i < n) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < n && text[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          afterClosingQuote = true;
          i++;
          continue;
        }
        if (ch == '\r') {
          if (i + 1 < n && text[i + 1] == '\n') i++;
          field.write('\n');
          i++;
          continue;
        }
        field.write(ch);
        i++;
        continue;
      }

      if (afterClosingQuote) {
        if (ch == ',') {
          finishField();
          i++;
          continue;
        }
        if (ch == '\n' || ch == '\r') {
          if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
          finishRecord();
          i++;
          continue;
        }
        throw const FormatException(
          'CSV: karakter tak terduga setelah kutipan penutup.',
        );
      }

      if (ch == '"' && atFieldStart) {
        inQuotes = true;
        atFieldStart = false; // field kutipan kosong tetap kolom
        i++;
        continue;
      }
      if (ch == ',') {
        finishField();
        i++;
        continue;
      }
      if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
        finishRecord();
        i++;
        continue;
      }
      field.write(ch);
      atFieldStart = false;
      i++;
    }

    if (inQuotes) {
      throw const FormatException('CSV: kutipan tidak ditutup.');
    }
    // `atFieldStart` false berarti ada kolom berjalan; record non-kosong
    // berarti ada koma trailing -> kolom kosong terakhir.
    if (!atFieldStart || record.isNotEmpty || field.isNotEmpty) {
      finishRecord();
    }
    return records;
  }

  /// Format tanggal ISO 8601 (YYYY-MM-DD).
  static String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static String _metadataLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n]+'), ' ');

  /// Quote field CSV:
  /// - Selalu dibungkus tanda kutip ganda.
  /// - Tanda kutip di dalam di-escape jadi dua kutip ("").
  /// - Newline dalam teks diganti spasi.
  /// - Field yang diawali karakter formula (=, +, -, @, |, %)
  ///   diawali spasi (CSV injection guard).
  static String _quoteField(String raw) {
    var s = raw
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    // CSV injection guard
    if (s.isNotEmpty && '=+-@|%'.contains(s[0])) {
      s = ' $s';
    }
    s = s.replaceAll('"', '""');
    return '"$s"';
  }
}

// ── Result type ───────────────────────────────────────────────────────────

enum _CsvExportStatus { success, empty, cancelled, stale, failure }

class CsvExportResult {
  final _CsvExportStatus _status;
  final String? errorMessage;

  const CsvExportResult._(this._status, {this.errorMessage});

  const CsvExportResult.success() : this._(_CsvExportStatus.success);
  const CsvExportResult.empty() : this._(_CsvExportStatus.empty);
  const CsvExportResult.cancelled() : this._(_CsvExportStatus.cancelled);
  const CsvExportResult.stale() : this._(_CsvExportStatus.stale);
  const CsvExportResult.failure(String message)
    : this._(_CsvExportStatus.failure, errorMessage: message);

  bool get isSuccess => _status == _CsvExportStatus.success;
  bool get isEmpty => _status == _CsvExportStatus.empty;
  bool get isCancelled => _status == _CsvExportStatus.cancelled;
  bool get isStale => _status == _CsvExportStatus.stale;
  bool get isFailure => _status == _CsvExportStatus.failure;
}
