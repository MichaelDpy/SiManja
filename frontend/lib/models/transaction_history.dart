import '../core/calendar_date.dart';
import 'transaction_model.dart';

/// C06 capability only. Reports still use the complete, mixed-schema listener.
abstract interface class TransactionHistoryRepository {
  Future<TransactionHistoryPage> loadHistory(
    String uid,
    TransactionHistoryQuery query, {
    TransactionHistoryCursor? after,
  });
}

/// Calendar components are inclusive at [from], exclusive at [until].
/// Only dateVersion=2 records are covered; legacy dates need reviewed migration
/// or the existing mixed-schema listener before they can contribute to totals.
class TransactionHistoryQuery {
  TransactionHistoryQuery({DateTime? from, DateTime? until, this.pageSize = 50})
    : from = from == null ? null : CalendarDate.canonical(from),
      until = until == null ? null : CalendarDate.canonical(until) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError('Ukuran halaman harus antara 1 dan 100.');
    }
    for (final boundary in [this.from, this.until]) {
      if (boundary != null &&
          (boundary.isBefore(DateTime.utc(1900)) ||
              boundary.isAfter(DateTime.utc(2201)))) {
        throw ArgumentError('Batas tanggal di luar rentang.');
      }
    }
    if (this.from != null &&
        this.until != null &&
        this.from!.isAfter(this.until!)) {
      throw ArgumentError('Awal periode melewati akhir periode.');
    }
  }

  final DateTime? from;
  final DateTime? until;
  final int pageSize;

  /// A cursor is local pagination state, never an authorization credential.
  /// Changing page size is allowed; changing owner or range requires refresh.
  void validateCursor(String uid, TransactionHistoryCursor? cursor) {
    if (cursor != null &&
        (cursor._uid != uid ||
            cursor._from != from ||
            cursor._until != until)) {
      throw ArgumentError('Cursor tidak cocok dengan akun atau periode.');
    }
  }
}

/// An opaque value cursor survives deletion of the boundary document.
/// It does not pin a database snapshot: date edits may move rows across pages;
/// inserts before it become visible when the consumer refreshes the first page.
class TransactionHistoryCursor {
  TransactionHistoryCursor._(
    String uid,
    TransactionHistoryQuery query,
    this.id,
    this.date,
  ) : _uid = uid,
      _from = query.from,
      _until = query.until;

  final String _uid;
  final DateTime? _from;
  final DateTime? _until;
  final String id;
  final DateTime date;
}

class TransactionHistoryPage {
  TransactionHistoryPage.fromLookahead({
    required String uid,
    required TransactionHistoryQuery query,
    required List<TransactionModel> records,
    TransactionHistoryCursor? after,
    required this.fromCache,
    required this.hasPendingWrites,
  }) : isFirstPage = after == null,
       fetchedDocuments = records.length {
    query.validateCursor(uid, after);
    if (records.length > query.pageSize + 1 ||
        records.any((row) => row.needsDateReview)) {
      throw ArgumentError('Halaman tidak sesuai cakupan tanggal kanonis.');
    }
    transactions = List.unmodifiable(records.take(query.pageSize));
    hasMore = records.length > query.pageSize;
    nextCursor = hasMore
        ? TransactionHistoryCursor._(
            uid,
            query,
            transactions.last.id,
            CalendarDate.canonical(transactions.last.date),
          )
        : null;
  }

  late final List<TransactionModel> transactions;
  late final bool hasMore;
  late final TransactionHistoryCursor? nextCursor;
  final bool isFirstPage;
  final int fetchedDocuments;
  final bool fromCache;
  final bool hasPendingWrites;

  bool get serverConfirmed => !fromCache && !hasPendingWrites;
  bool get isLastPage => !hasMore;

  /// Even the last page is not the entire range if earlier pages were fetched.
  /// This never asserts that legacy rows or a cross-request snapshot are covered.
  bool get isCompleteForCanonicalRange =>
      isFirstPage && isLastPage && serverConfirmed;

  bool get includesLegacyDates => false;
}
