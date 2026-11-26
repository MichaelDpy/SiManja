import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/repositories/transaction_repository.dart';

class MemoryTransactions implements TransactionRepository {
  final rows = <String, List<TransactionModel>>{};
  final events = <String, StreamController<TransactionSnapshot>>{};
  final subscriptions = <String, int>{};
  int idCounter = 0;
  int writes = 0;
  bool emitInitial = true;
  Completer<void>? pendingWrite;
  Object? writeFailure;
  Object? failureAfterCommit;
  int committedWrites = 0;
  final attemptedIds = <String>[];

  void _committed() {
    committedWrites++;
    final error = failureAfterCommit;
    failureAfterCommit = null;
    if (error != null) throw error;
  }

  @override
  String newId(String uid) => 'generated-$uid-${++idCounter}';
  @override
  Stream<TransactionSnapshot> watch(String uid) => Stream.multi((sink) {
    subscriptions[uid] = (subscriptions[uid] ?? 0) + 1;
    final controller = events.putIfAbsent(
      uid,
      () => StreamController.broadcast(sync: true),
    );
    final subscription = controller.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    if (emitInitial) sink.add(TransactionSnapshot(rows[uid] ?? []));
    sink.onCancel = () async {
      subscriptions[uid] = subscriptions[uid]! - 1;
      await subscription.cancel();
    };
  });

  void emit(
    String uid,
    List<TransactionModel> transactions, {
    bool cache = false,
    bool pending = false,
  }) {
    rows[uid] = List.from(transactions);
    events[uid]?.add(
      TransactionSnapshot(
        transactions,
        fromCache: cache,
        hasPendingWrites: pending,
      ),
    );
  }

  Future<void> _write() async {
    writes++;
    await pendingWrite?.future;
    if (writeFailure != null) throw writeFailure!;
  }

  @override
  Future<void> add(String uid, TransactionModel transaction) async {
    attemptedIds.add(transaction.id);
    await _write();
    final existing = (rows[uid] ?? [])
        .where((item) => item.id == transaction.id)
        .firstOrNull;
    if (existing != null) {
      if (mapEquals(
        TransactionMapper.toMap(existing),
        TransactionMapper.toMap(transaction),
      )) {
        return;
      }
      throw const RecordConflict(ConflictReason.changed);
    }
    emit(uid, [transaction, ...?rows[uid]]);
    _committed();
  }

  @override
  Future<void> update(
    String uid,
    String id,
    TransactionModel transaction,
  ) async {
    await _write();
    if (!(rows[uid] ?? []).any((item) => item.id == id)) {
      throw StateError('Missing ID');
    }
    emit(
      uid,
      rows[uid]!.map((item) => item.id == id ? transaction : item).toList(),
    );
    _committed();
  }

  @override
  Future<void> delete(
    String uid,
    String id, {
    RecordVersion? expectedVersion,
  }) async {
    await _write();
    if (!(rows[uid] ?? []).any((item) => item.id == id)) return;
    emit(uid, (rows[uid] ?? []).where((item) => item.id != id).toList());
    _committed();
  }
}
