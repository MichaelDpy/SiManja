import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transaction_model.dart';

/// Utilitas ekspor transaksi ke file CSV.
///
/// Format kolom:
///   tanggal_iso, kategori, keterangan, jenis, nominal_rupiah
///
/// Aturan keamanan:
/// - Semua field teks di-quote dan koma/kutip/newline di-escape.
/// - Field yang diawali =, +, -, @ diawali dengan spasi (CSV injection guard).
/// - Encoding UTF-8 dengan BOM agar Excel membuka dengan benar.
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
  }) async {
    if (transactions.isEmpty) {
      return const CsvExportResult.empty();
    }

    try {
      final csvBytes = _buildCsv(transactions, periodLabel);

      final dir = await getTemporaryDirectory();
      final safePeriod = periodLabel
          .replaceAll(RegExp(r'[^\w\-]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final fileName = 'simanja_transaksi_$safePeriod.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(csvBytes, flush: true);

      // share_plus v10 masih menggunakan API static Share.shareXFiles
      final result = await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'Data Transaksi SIMANJA — $periodLabel');

      if (result.status == ShareResultStatus.dismissed) {
        return const CsvExportResult.cancelled();
      }
      return const CsvExportResult.success();
    } catch (e) {
      return CsvExportResult.failure('$e');
    }
  }

  // ── CSV builder ───────────────────────────────────────────────────────

  static List<int> _buildCsv(
    List<TransactionModel> transactions,
    String periodLabel,
  ) {
    final buf = StringBuffer();

    // Header baris komentar (diawali # → bukan formula)
    buf.writeln('# SIMANJA — Ekspor Data Transaksi');
    buf.writeln('# Periode: $periodLabel');
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
          tx.amount.toInt().toString(),
        ].map(_quoteField).join(','),
      );
    }

    // UTF-8 BOM agar Excel Windows membuka dengan encoding benar
    const bom = [0xEF, 0xBB, 0xBF];
    return [...bom, ...buf.toString().codeUnits];
  }

  /// Format tanggal ISO 8601 (YYYY-MM-DD).
  static String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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

enum _CsvExportStatus { success, empty, cancelled, failure }

class CsvExportResult {
  final _CsvExportStatus _status;
  final String? errorMessage;

  const CsvExportResult._(this._status, {this.errorMessage});

  const CsvExportResult.success() : this._(_CsvExportStatus.success);
  const CsvExportResult.empty() : this._(_CsvExportStatus.empty);
  const CsvExportResult.cancelled() : this._(_CsvExportStatus.cancelled);
  const CsvExportResult.failure(String message)
    : this._(_CsvExportStatus.failure, errorMessage: message);

  bool get isSuccess => _status == _CsvExportStatus.success;
  bool get isEmpty => _status == _CsvExportStatus.empty;
  bool get isCancelled => _status == _CsvExportStatus.cancelled;
  bool get isFailure => _status == _CsvExportStatus.failure;
}
