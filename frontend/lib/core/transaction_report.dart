import 'dart:convert';

import '../models/transaction_model.dart';
import 'calendar_date.dart';
import 'finance_summary.dart';

enum ReportSort { number, category, amount, date }

/// One immutable observation of the full collection listener, never a page.
class ReportSource {
  ReportSource({
    required List<TransactionModel> transactions,
    required this.token,
    required this.uid,
    required this.sessionRevision,
    required this.confirmed,
    required this.loading,
    required this.pending,
    required this.fromCache,
    required this.error,
  }) : transactions = List.unmodifiable(transactions);

  final List<TransactionModel> transactions;
  final Object token;
  final String? uid;
  final int sessionRevision;
  final bool confirmed;
  final bool loading;
  final bool pending;
  final bool fromCache;
  final String? error;
  bool get canExport => confirmed && !loading && !pending && error == null;

  bool sameInput(ReportSource other) =>
      identical(token, other.token) &&
      uid == other.uid &&
      sessionRevision == other.sessionRevision &&
      confirmed == other.confirmed &&
      loading == other.loading &&
      pending == other.pending &&
      fromCache == other.fromCache &&
      error == other.error;
}

class ReportCriteria {
  ReportCriteria({
    DateTime? from,
    DateTime? until,
    String search = '',
    this.sort = ReportSort.date,
    this.ascending = false,
  }) : from = from == null ? null : CalendarDate.canonical(from),
       until = until == null ? null : CalendarDate.canonical(until),
       search = search.trim().toLowerCase();

  final DateTime? from;
  final DateTime? until;
  final String search;
  final ReportSort sort;
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is ReportCriteria &&
      other.from == from &&
      other.until == until &&
      other.search == search &&
      other.sort == sort &&
      other.ascending == ascending;
  @override
  int get hashCode => Object.hash(from, until, search, sort, ascending);
}

class TransactionReport {
  TransactionReport(this.source, this.criteria) {
    final matching = source.transactions.where((row) {
      final day = CalendarDate.canonical(row.date);
      return (criteria.from == null || !day.isBefore(criteria.from!)) &&
          (criteria.until == null || day.isBefore(criteria.until!)) &&
          (criteria.search.isEmpty ||
              row.category.toLowerCase().contains(criteria.search) ||
              row.description.toLowerCase().contains(criteria.search));
    }).toList();
    matching.sort((a, b) {
      var comparison = switch (criteria.sort) {
        ReportSort.category => a.category.compareTo(b.category),
        ReportSort.amount => (a.isIncome ? a.amount : -a.amount).compareTo(
          b.isIncome ? b.amount : -b.amount,
        ),
        ReportSort.number || ReportSort.date => CalendarDate.canonical(
          a.date,
        ).compareTo(CalendarDate.canonical(b.date)),
      };
      if (comparison == 0 && criteria.sort == ReportSort.category) {
        comparison = CalendarDate.canonical(b.date)
            .compareTo(CalendarDate.canonical(a.date));
      }
      if (comparison == 0) comparison = _compareIds(a.id, b.id);
      return criteria.ascending ? comparison : -comparison;
    });
    rows = List.unmodifiable(matching);
  }

  final ReportSource source;
  final ReportCriteria criteria;
  late final List<TransactionModel> rows;
  BigInt get income => FinanceSummary.totalIncome(rows);
  BigInt get expense => FinanceSummary.totalExpense(rows);
  BigInt get net => income - expense;

  /// Matches Firestore document-ID ordering even for non-BMP characters.
  static int _compareIds(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    for (var i = 0; i < left.length && i < right.length; i++) {
      final difference = left[i].compareTo(right[i]);
      if (difference != 0) return difference;
    }
    return left.length.compareTo(right.length);
  }
}
