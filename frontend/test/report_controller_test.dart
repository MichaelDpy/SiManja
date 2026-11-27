import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/app_state.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/finance_summary.dart';
import 'package:simanja/core/report_controller.dart';
import 'package:simanja/core/transaction_report.dart';
import 'package:simanja/models/transaction_model.dart';

import 'support/memory_history.dart';
import 'support/memory_profiles.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  late MemoryHistory repository;
  late AppState state;
  late ReportController controller;
  setUp(() async {
    repository = MemoryHistory()..rows['A'] = reportFixture();
    state = AppState.forTesting(
      profiles: MemoryProfiles(),
      transactions: repository,
    );
    await state.beginSession('A', 'a@example.test');
    await tick();
    controller = ReportController(state);
    await tick();
  });
  tearDown(() {
    controller.dispose();
    state.dispose();
  });

  test(
    'all pages cover dataset once while totals, charts and CSV remain full',
    () async {
      expect(controller.usesServerPaging, isTrue);
      expect(repository.queries, 0);
      expect(controller.visibleRows, hasLength(50));
      final collected = <String>[];
      do {
        collected.addAll(controller.visibleRows.map((row) => row.id));
        expect(
          controller.report.income,
          FinanceSummary.totalIncome(reportFixture()),
        );
        expect(state.totalIncome, controller.report.income);
        if (!controller.hasNext) break;
        await controller.nextPage();
      } while (true);
      expect(collected, hasLength(137));
      expect(collected.toSet(), hasLength(137));
      expect(controller.firstRow, 101);
      expect(controller.lastRow, 137);
      final frozen = controller.captureExport();
      expect(frozen.rows, hasLength(137));
      expect(
        utf8.decode(CsvExporter.encode(frozen.rows, 'Nov 2026')),
        contains('# Jumlah baris: 137'),
      );
      await controller.previousPage();
      expect(controller.firstRow, 51);
    },
  );

  test(
    'search across hidden pages controls both totals and frozen export',
    () async {
      controller.configure(
        ReportCriteria(
          from: DateTime(2026, 11),
          until: DateTime(2026, 12),
          search: ' NEEDLE ',
        ),
      );
      expect(controller.report.rows, hasLength(2));
      expect(controller.visibleRows.map((row) => row.id), [
        'row-136',
        'row-000',
      ]);
      expect(
        controller.report.income,
        BigInt.from(9007199254740991) + BigInt.from(236),
      );
      expect(controller.report.expense, BigInt.zero);
      expect(controller.usesServerPaging, isFalse);
      final frozen = controller.captureExport();
      repository.emit('A', []);
      await tick();
      expect(controller.report.rows, isEmpty);
      expect(frozen.rows, hasLength(2));
      expect(() => frozen.rows.clear(), throwsUnsupportedError);
    },
  );

  test(
    'cache partial and empty stay unconfirmed until reload reaches server',
    () async {
      repository.emit('A', reportFixture(4), cache: true);
      await tick();
      expect(controller.report.source.fromCache, isTrue);
      expect(controller.report.rows, hasLength(4));
      expect(controller.usesServerPaging, isFalse);
      expect(controller.captureExport, throwsStateError);
      repository.emit('A', [], cache: true);
      await tick();
      expect(controller.captureExport, throwsStateError);
      repository.rows['A'] = reportFixture();
      await state.retryTransactions();
      await tick();
      await tick();
      expect(controller.captureExport().rows, hasLength(137));
      expect(controller.usesServerPaging, isTrue);
    },
  );

  test(
    'legacy and calendar bounds retain complete data through local paging',
    () async {
      final legacy = TransactionModel(
        id: 'legacy',
        category: 'Gaji',
        description: 'Legacy',
        amount: 3,
        isIncome: true,
        date: DateTime(2026, 11, 1),
        legacyDate: const LegacyTransactionDate(1, 0),
      );
      repository.emit('A', [
        ...reportFixture(),
        legacy,
        TransactionModel(
          id: 'end-boundary',
          category: 'Gaji',
          description: 'End',
          amount: 3,
          isIncome: true,
          date: DateTime(2026, 12, 1),
        ),
      ]);
      await tick();
      controller.configure(
        ReportCriteria(from: DateTime(2026, 11), until: DateTime(2026, 12)),
      );
      expect(controller.usesServerPaging, isFalse);
      expect(controller.report.rows, hasLength(138));
      expect(
        controller.report.income,
        FinanceSummary.totalIncome(reportFixture()) + BigInt.from(3),
      );
    },
  );

  test(
    'query failure/mismatch keeps complete snapshot and reload recovers',
    () async {
      repository.queryFailure = StateError('sensitive SDK details');
      await state.retryTransactions();
      await tick();
      await tick();
      await controller.nextPage();
      expect(controller.pageNotice, isNotNull);
      expect(controller.pageNotice, isNot(contains('sensitive')));
      expect(controller.usesServerPaging, isFalse);
      expect(controller.captureExport().rows, hasLength(137));
      expect(controller.firstRow, 51);
      repository.queryFailure = null;
      repository.mismatchedResult = true;
      await state.retryTransactions();
      await tick();
      await tick();
      await controller.nextPage();
      expect(
        controller.visibleRows.first.amount,
        controller.report.rows[50].amount,
      );
      expect(controller.usesServerPaging, isFalse);
      repository.mismatchedResult = false;
      await state.retryTransactions();
      await tick();
      await tick();
      await controller.nextPage();
      expect(controller.usesServerPaging, isTrue);
      expect(controller.pageNotice, isNull);
    },
  );

  test(
    'realtime invalidates page and late reply cannot replace new report',
    () async {
      await controller.nextPage();
      repository.hold = true;
      final oldRead = controller.nextPage();
      final old = repository.requests.last;
      repository.emit('A', reportFixture(138));
      await tick();
      expect(controller.firstRow, 1);
      repository.emit('A', reportFixture(139));
      await tick();
      final latestRead = controller.nextPage();
      final latest = repository.requests.last;
      old.completion.complete(old.result);
      await oldRead;
      await tick();
      expect(controller.report.rows, hasLength(139));
      expect(controller.firstRow, 51);
      expect(controller.loadingPage, isTrue);
      latest.completion.complete(latest.result);
      await latestRead;
      await tick();
      expect(controller.loadingPage, isFalse);
      expect(controller.visibleRows.first.id, controller.report.rows[50].id);
    },
  );

  test(
    'same UID new session rejects old async result and export context',
    () async {
      repository.hold = true;
      controller.configure(ReportCriteria(from: DateTime(2026, 11)));
      final oldRead = controller.nextPage();
      final old = repository.requests.last;
      final snapshot = controller.captureExport();
      state.clearSession();
      repository.rows['A'] = reportFixture(2);
      await state.beginSession('A', 'a@example.test');
      await tick();
      old.completion.complete(old.result);
      await oldRead;
      await tick();
      expect(controller.report.rows, hasLength(2));
      expect(controller.loadingPage, isFalse);
      expect(snapshot.source.uid, state.sessionUid);
      expect(snapshot.source.sessionRevision, isNot(state.sessionRevision));
    },
  );

  test('navigation remains available during optional slow query', () async {
    repository.hold = true;
    controller.configure(ReportCriteria(from: DateTime(2026, 11)));
    final oldRead = controller.nextPage();
    final pending = repository.requests.last;
    expect(controller.loadingPage, isTrue);
    await controller.nextPage();
    expect(controller.firstRow, 101);
    expect(controller.loadingPage, isFalse);
    pending.completion.complete(pending.result);
    await oldRead;
    await tick();
    expect(controller.firstRow, 101);
    expect(controller.report.rows, hasLength(137));
  });

  test(
    'sort/search changes reset paging without losing filtered results',
    () async {
      await controller.nextPage();
      controller.configure(
        ReportCriteria(sort: ReportSort.amount, ascending: true),
      );
      expect(controller.firstRow, 1);
      expect(controller.usesServerPaging, isFalse);
      expect(controller.report.rows.last.id, 'row-000');
      controller.configure(ReportCriteria(search: 'absent'));
      expect(controller.visibleRows, isEmpty);
      expect(controller.report.net, BigInt.zero);
      expect(controller.firstRow, 0);
    },
  );
}
