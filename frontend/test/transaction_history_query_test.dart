import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/models/transaction_history.dart';
import 'package:simanja/models/transaction_model.dart';
import 'package:simanja/repositories/transaction_repository.dart';

import 'support/recording_firestore.dart';

TransactionModel row(String id) => TransactionModel(
  id: id,
  category: 'Gaji',
  description: 'Synthetic query test',
  amount: 100,
  isIncome: true,
  date: DateTime.utc(2026, 11, 27),
);

RecordingDocument document(String id) => RecordingDocument(id, {
  ...TransactionMapper.toMap(row(id)),
  'createdAt': Timestamp(1, 0),
  'updatedAt': Timestamp(1, 0),
  'revision': 1,
});

void main() {
  test('query canonicalizes calendar components and caps the page size', () {
    final query = TransactionHistoryQuery(
      from: DateTime(2026, 11, 1, 23),
      until: DateTime.utc(2026, 12),
    );
    expect(query.from, DateTime.utc(2026, 11));
    expect(query.until, DateTime.utc(2026, 12));
    expect(query.pageSize, 50);
    for (final size in [-1, 0, 101, 1000000]) {
      expect(
        () => TransactionHistoryQuery(pageSize: size),
        throwsArgumentError,
      );
    }
    for (final boundary in [DateTime.utc(1899), DateTime.utc(2201, 1, 2)]) {
      expect(
        () => TransactionHistoryQuery(from: boundary),
        throwsArgumentError,
      );
      expect(
        () => TransactionHistoryQuery(until: boundary),
        throwsArgumentError,
      );
    }
    expect(
      () => TransactionHistoryQuery(
        from: DateTime.utc(2026, 12),
        until: DateTime.utc(2026, 11),
      ),
      throwsArgumentError,
    );
  });

  test(
    'production query uses owner path, v2 range, both sort keys and server',
    () async {
      final sdk = RecordingFirestore();
      final repository = FirestoreTransactionRepository(sdk);
      await repository.loadHistory(
        'owner-A',
        TransactionHistoryQuery(
          from: DateTime(2026, 11),
          until: DateTime(2026, 12),
          pageSize: 2,
        ),
      );
      expect(sdk.paths, ['users', 'owner-A', 'transactions']);
      final filters = sdk.calls
          .where((call) => call.memberName == #where)
          .toList();
      expect(filters[0].positionalArguments, ['dateVersion']);
      expect(filters[0].namedArguments[#isEqualTo], 2);
      expect(filters[1].positionalArguments, ['date']);
      expect(
        filters[1].namedArguments[#isGreaterThanOrEqualTo],
        Timestamp.fromDate(DateTime.utc(2026, 11)),
      );
      expect(
        filters[2].namedArguments[#isLessThan],
        Timestamp.fromDate(DateTime.utc(2026, 12)),
      );
      final order = sdk.calls
          .where((call) => call.memberName == #orderBy)
          .toList();
      expect(order[0].positionalArguments, ['date']);
      expect(order[1].positionalArguments, [FieldPath.documentId]);
      expect(
        order.every((call) => call.namedArguments[#descending] == true),
        isTrue,
      );
      expect(
        sdk.calls
            .singleWhere((call) => call.memberName == #limit)
            .positionalArguments,
        [3],
      );
      final options = sdk.calls.last.positionalArguments.single as GetOptions;
      expect(options.source, Source.server);
    },
  );

  test(
    'lookahead is not exposed or skipped; cursor uses last displayed row',
    () async {
      final sdk = RecordingFirestore()
        ..documents = [document('c'), document('b'), document('a')];
      final repository = FirestoreTransactionRepository(sdk);
      final query = TransactionHistoryQuery(pageSize: 2);
      final first = await repository.loadHistory('A', query);
      expect(first.transactions.map((item) => item.id), ['c', 'b']);
      expect(first.fetchedDocuments, 3);
      expect(first.hasMore, isTrue);
      expect(first.isCompleteForCanonicalRange, isFalse);
      expect(first.includesLegacyDates, isFalse);
      expect(() => first.transactions.clear(), throwsUnsupportedError);
      sdk.documents = [document('a')];
      sdk.calls.clear();
      final last = await repository.loadHistory(
        'A',
        query,
        after: first.nextCursor,
      );
      final cursor = sdk.calls.singleWhere(
        (call) => call.memberName == #startAfter,
      );
      expect(cursor.positionalArguments.single, [
        Timestamp.fromDate(row('b').date),
        'b',
      ]);
      expect(last.isLastPage, isTrue);
      expect(last.nextCursor, isNull);
      expect(last.isFirstPage, isFalse);
      expect(last.isCompleteForCanonicalRange, isFalse);
    },
  );

  test(
    'cursor cannot be reused across owners/ranges or invalid UID paths',
    () async {
      final sdk = RecordingFirestore()
        ..documents = [document('c'), document('b')];
      final repository = FirestoreTransactionRepository(sdk);
      final query = TransactionHistoryQuery(pageSize: 1);
      final page = await repository.loadHistory('A', query);
      final before = sdk.calls.length;
      for (final uid in ['B', '', 'A/other', '..']) {
        await expectLater(
          repository.loadHistory(uid, query, after: page.nextCursor),
          throwsArgumentError,
        );
      }
      await expectLater(
        repository.loadHistory(
          'A',
          TransactionHistoryQuery(from: DateTime.utc(2026, 11)),
          after: page.nextCursor,
        ),
        throwsArgumentError,
      );
      expect(sdk.calls.length, before);
      sdk.documents = [];
      await repository.loadHistory(
        'A',
        TransactionHistoryQuery(pageSize: 100),
        after: page.nextCursor,
      );
    },
  );

  test(
    'exact page and empty range are complete only for canonical server data',
    () async {
      final sdk = RecordingFirestore()
        ..documents = [document('b'), document('a')];
      final repository = FirestoreTransactionRepository(sdk);
      final query = TransactionHistoryQuery(pageSize: 2);
      final exact = await repository.loadHistory('A', query);
      expect(exact.hasMore, isFalse);
      expect(exact.isCompleteForCanonicalRange, isTrue);
      expect(exact.includesLegacyDates, isFalse);
      sdk.documents = [];
      final empty = await repository.loadHistory('A', query);
      expect(empty.transactions, isEmpty);
      expect(empty.nextCursor, isNull);
      expect(empty.isCompleteForCanonicalRange, isTrue);
      sdk.fromCache = true;
      expect(
        (await repository.loadHistory('A', query)).serverConfirmed,
        isFalse,
      );
      sdk.fromCache = false;
      sdk.pending = true;
      expect(
        (await repository.loadHistory('A', query)).isCompleteForCanonicalRange,
        isFalse,
      );
    },
  );

  test(
    'server errors and malformed data are not converted to empty success',
    () async {
      final sdk = RecordingFirestore();
      final repository = FirestoreTransactionRepository(sdk);
      for (final code in [
        'unavailable',
        'permission-denied',
        'failed-precondition',
      ]) {
        final error = FirebaseException(plugin: 'cloud_firestore', code: code);
        sdk.failure = error;
        await expectLater(
          repository.loadHistory('A', TransactionHistoryQuery()),
          throwsA(same(error)),
        );
      }
      sdk.failure = null;
      sdk.documents = [RecordingDocument('bad', {})];
      await expectLater(
        repository.loadHistory('A', TransactionHistoryQuery()),
        throwsFormatException,
      );
    },
  );

  test('page factory rejects oversized results and legacy rows', () {
    final query = TransactionHistoryQuery(pageSize: 1);
    expect(
      () => TransactionHistoryPage.fromLookahead(
        uid: 'A',
        query: query,
        records: [row('c'), row('b'), row('a')],
        fromCache: false,
        hasPendingWrites: false,
      ),
      throwsArgumentError,
    );
    final data = {
      ...TransactionMapper.toMap(row('legacy')),
      'createdAt': Timestamp(1, 0),
      'updatedAt': Timestamp(1, 0),
    };
    data.remove('dateVersion');
    expect(
      () => TransactionHistoryPage.fromLookahead(
        uid: 'A',
        query: query,
        records: [TransactionMapper.fromMap('legacy', data)],
        fromCache: false,
        hasPendingWrites: false,
      ),
      throwsArgumentError,
    );
  });
}
