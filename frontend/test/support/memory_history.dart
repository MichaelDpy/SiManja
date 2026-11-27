import 'dart:async';

import 'package:simanja/core/transaction_report.dart';
import 'package:simanja/models/transaction_history.dart';
import 'package:simanja/models/transaction_model.dart';

import 'memory_transactions.dart';

class MemoryHistory extends MemoryTransactions
    implements TransactionHistoryRepository {
  int queries = 0;
  bool hold = false;
  Object? queryFailure;
  bool mismatchedResult = false;
  final requests =
      <
        ({
          Completer<TransactionHistoryPage> completion,
          TransactionHistoryPage result,
        })
      >[];

  @override
  Future<TransactionHistoryPage> loadHistory(
    String uid,
    TransactionHistoryQuery query, {
    TransactionHistoryCursor? after,
  }) async {
    queries++;
    query.validateCursor(uid, after);
    if (queryFailure case final failure?) throw failure;
    final report = TransactionReport(
      ReportSource(
        transactions: (rows[uid] ?? [])
            .where((row) => !row.needsDateReview)
            .toList(),
        token: Object(),
        uid: uid,
        sessionRevision: 1,
        confirmed: true,
        loading: false,
        pending: false,
        fromCache: false,
        error: null,
      ),
      ReportCriteria(from: query.from, until: query.until),
    );
    final start = after == null
        ? 0
        : report.rows.indexWhere((row) => row.id == after.id) + 1;
    var records = report.rows.skip(start).take(query.pageSize + 1).toList();
    if (mismatchedResult && records.isNotEmpty) {
      records = [records.first.copyWith(amount: 42), ...records.skip(1)];
    }
    final result = TransactionHistoryPage.fromLookahead(
      uid: uid,
      query: query,
      records: records,
      after: after,
      fromCache: false,
      hasPendingWrites: false,
    );
    if (!hold) return result;
    final completion = Completer<TransactionHistoryPage>();
    requests.add((completion: completion, result: result));
    return completion.future;
  }
}

List<TransactionModel> reportFixture([int length = 137]) => List.generate(
  length,
  (i) => TransactionModel(
    id: 'row-${i.toString().padLeft(3, '0')}',
    category: i.isEven ? 'Gaji' : 'Makanan',
    description: (i == 0 || i == length - 1) ? 'needle $i' : 'Entry $i',
    amount: i == 0 ? 9007199254740991 : 100 + i.toDouble(),
    isIncome: i.isEven,
    date: DateTime.utc(2026, 11, 27),
  ),
);
