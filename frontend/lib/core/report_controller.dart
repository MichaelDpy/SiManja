import 'package:flutter/foundation.dart';

import '../models/transaction_history.dart';
import '../models/transaction_model.dart';
import 'app_state.dart';
import 'transaction_report.dart';

/// Paging affects the table only. Totals and CSV always use [report.rows].
class ReportController extends ChangeNotifier {
  ReportController(this.state, {this.pageSize = 50}) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError('Ukuran halaman salah.');
    }
    state.addListener(_onSource);
    _rebuild();
  }

  final AppState state;
  final int pageSize;
  ReportCriteria _criteria = ReportCriteria();
  late TransactionReport report;
  int pageIndex = 0;
  bool loadingPage = false;
  String? pageNotice;
  int _epoch = 0;
  bool _disposed = false;
  bool _fallback = false;
  List<TransactionModel>? _remoteRows;
  final _starts = <int, TransactionHistoryCursor?>{0: null};

  int get firstRow => report.rows.isEmpty ? 0 : pageIndex * pageSize + 1;
  int get lastRow =>
      (pageIndex * pageSize + pageSize).clamp(0, report.rows.length);
  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => lastRow < report.rows.length;
  List<TransactionModel> get visibleRows =>
      _remoteRows ??
      List.unmodifiable(report.rows.skip(pageIndex * pageSize).take(pageSize));
  bool get usesServerPaging =>
      !_fallback &&
      state.historyRepository != null &&
      report.source.canExport &&
      report.source.uid != null &&
      report.rows.length > pageSize &&
      _criteria.search.isEmpty &&
      _criteria.sort == ReportSort.date &&
      !_criteria.ascending &&
      !report.rows.any((row) => row.needsDateReview);

  void configure(ReportCriteria criteria) {
    if (_criteria == criteria) return;
    _criteria = criteria;
    _rebuild();
  }

  void _onSource() {
    if (!report.source.sameInput(state.reportSource)) _rebuild();
  }

  void _rebuild() {
    _epoch++;
    report = TransactionReport(state.reportSource, _criteria);
    pageIndex = 0;
    _starts
      ..clear()
      ..[0] = null;
    _fallback = false;
    _remoteRows = null;
    pageNotice = null;
    loadingPage = false;
    if (usesServerPaging) {
      // The full confirmed observation already supplies the first page/cursor.
      // Read an additional server page only when the user actually navigates.
      _starts[1] = TransactionHistoryPage.fromLookahead(
        uid: report.source.uid!,
        query: TransactionHistoryQuery(
          from: _criteria.from,
          until: _criteria.until,
          pageSize: pageSize,
        ),
        records: report.rows.take(pageSize + 1).toList(),
        fromCache: false,
        hasPendingWrites: false,
      ).nextCursor;
    }
    notifyListeners();
  }

  Future<void> nextPage() async {
    if (!hasNext) return;
    _leavePendingRead();
    pageIndex++;
    _remoteRows = null;
    if (usesServerPaging) {
      await _loadPage();
    } else {
      notifyListeners();
    }
  }

  Future<void> previousPage() async {
    if (!hasPrevious) return;
    _leavePendingRead();
    pageIndex--;
    _remoteRows = null;
    if (usesServerPaging) {
      await _loadPage();
    } else {
      notifyListeners();
    }
  }

  void _leavePendingRead() {
    if (!loadingPage) return;
    // The full listener snapshot already supports navigation. Detach the UI
    // result of an optional slow read; this does not cancel the SDK request.
    _epoch++;
    loadingPage = false;
    _fallback = true;
  }

  Future<void> _loadPage() async {
    final repository = state.historyRepository!;
    final epoch = ++_epoch;
    final index = pageIndex;
    final captured = report;
    loadingPage = true;
    notifyListeners();
    bool active() =>
        !_disposed &&
        epoch == _epoch &&
        captured.source.sameInput(state.reportSource);
    try {
      final page = await repository.loadHistory(
        captured.source.uid!,
        TransactionHistoryQuery(
          from: _criteria.from,
          until: _criteria.until,
          pageSize: pageSize,
        ),
        after: _starts[index],
      );
      if (!active()) return;
      final expected = captured.rows
          .skip(index * pageSize)
          .take(pageSize)
          .toList();
      // Mutable pages are never accepted as a second report dataset. If they
      // diverge, the complete listener observation remains authoritative.
      if (!page.serverConfirmed ||
          page.transactions.length != expected.length ||
          page.hasMore !=
              (index * pageSize + expected.length < captured.rows.length) ||
          !List.generate(
            expected.length,
            (i) => _sameRow(expected[i], page.transactions[i]),
          ).every((same) => same)) {
        _useSnapshot();
      } else {
        _remoteRows = page.transactions;
        _starts[index + 1] = page.nextCursor;
      }
    } catch (_) {
      if (active()) _useSnapshot();
    } finally {
      if (active()) {
        loadingPage = false;
        notifyListeners();
      }
    }
  }

  void _useSnapshot() {
    _fallback = true;
    _remoteRows = null;
    pageNotice = 'Riwayat menggunakan data yang sudah dimuat. Muat ulang untuk mencoba lagi.';
  }

  static bool _sameRow(TransactionModel a, TransactionModel b) =>
      a.id == b.id &&
      a.category == b.category &&
      a.description == b.description &&
      a.amount == b.amount &&
      a.isIncome == b.isIncome &&
      a.date == b.date &&
      a.version == b.version &&
      !b.needsDateReview;

  TransactionReport captureExport() {
    if (!report.source.canExport) {
      throw StateError(
        'Tunggu data lengkap dikonfirmasi server sebelum ekspor.',
      );
    }
    return report;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    state.removeListener(_onSource);
    super.dispose();
  }
}
