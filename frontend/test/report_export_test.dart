import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/csv_exporter.dart';
import 'package:simanja/core/session_artifacts.dart';

import 'support/memory_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const sharing = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late List<MethodCall> shares;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('simanja-c07-export-test-');
    SessionExportStore.useForTesting(SessionExportStore());
    shares = [];
    messenger.setMockMethodCallHandler(paths, (_) async => temp.path);
    messenger.setMockMethodCallHandler(sharing, (call) async {
      shares.add(call);
      return 'synthetic-target';
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(sharing, null);
    expect(temp.parent.absolute.path, Directory.systemTemp.absolute.path);
    expect(
      temp.path.split(Platform.pathSeparator).last,
      startsWith('simanja-c07-export-test-'),
    );
    await temp.delete(recursive: true);
  });

  test('file encodes all frozen rows before await; overlapping exports get unique paths', () async {
    final gate = Completer<String>();
    messenger.setMockMethodCallHandler(paths, (_) => gate.future);
    final rows = reportFixture();
    final request = CsvExporter.export(
      transactions: rows,
      periodLabel: 'Nov 2026',
      isCurrent: () => true,
    );
    rows.clear();
    gate.complete(temp.path);
    expect((await request).isSuccess, isTrue);
    final firstPath = (shares.single.arguments as Map)['paths'][0] as String;
    final csv = utf8.decode(await File(firstPath).readAsBytes());
    expect(csv, contains('# Jumlah baris: 137'));
    expect(csv, contains('needle 0'));
    expect(csv, contains('9007199254740991'));
    await CsvExporter.export(
      transactions: reportFixture(1),
      periodLabel: 'Nov 2026',
    );
    final secondPath = (shares.last.arguments as Map)['paths'][0] as String;
    expect(secondPath, isNot(firstPath));
    expect(utf8.decode(await File(firstPath).readAsBytes()), csv);
  });

  test(
    'session ABA while obtaining directory aborts before file/share',
    () async {
      final gate = Completer<String>();
      messenger.setMockMethodCallHandler(paths, (_) => gate.future);
      var revision = 1;
      final request = CsvExporter.export(
        transactions: reportFixture(),
        periodLabel: 'Nov 2026',
        isCurrent: () => revision == 1,
      );
      revision =
          3; // same UID can be signed in again; the captured revision differs
      gate.complete(temp.path);
      expect((await request).isStale, isTrue);
      expect(shares, isEmpty);
      expect(
        await temp.list(recursive: true).where((item) => item is File).toList(),
        isEmpty,
      );
    },
  );

  test(
    'session change after file write is checked before invoking share',
    () async {
      final result = await CsvExporter.export(
        transactions: reportFixture(),
        periodLabel: 'Nov 2026',
        isCurrent: () =>
            temp.listSync(recursive: true).whereType<File>().isEmpty,
      );
      expect(result.isStale, isTrue);
      expect(shares, isEmpty);
      expect(
        await temp.list(recursive: true).where((item) => item is File).toList(),
        isEmpty,
      );
    },
  );

  test('session change during platform share suppresses old success; launch cannot be undone', () async {
    final gate = Completer<String>();
    final launched = Completer<void>();
    var active = true;
    messenger.setMockMethodCallHandler(sharing, (call) {
      shares.add(call);
      launched.complete();
      return gate.future;
    });
    final request = CsvExporter.export(
      transactions: reportFixture(),
      periodLabel: 'Nov 2026',
      isCurrent: () => active,
    );
    await launched.future;
    active = false;
    gate.complete('synthetic-target');
    expect((await request).isStale, isTrue);
    expect(shares, hasLength(1));
  });

  test('invalid context does no I/O and plugin errors reveal no filesystem details', () async {
    expect(
      (await CsvExporter.export(
        transactions: reportFixture(),
        periodLabel: 'Nov',
        isCurrent: () => false,
      )).isStale,
      isTrue,
    );
    expect(shares, isEmpty);
    messenger.setMockMethodCallHandler(
      paths,
      (_) => throw PlatformException(code: 'secret-path'),
    );
    final result = await CsvExporter.export(
      transactions: reportFixture(),
      periodLabel: 'Nov',
    );
    expect(result.isFailure, isTrue);
    expect(result.errorMessage, isNot(contains('secret-path')));
  });

  test('CSV metadata records search scope without injecting new rows', () {
    final text = utf8.decode(
      CsvExporter.encode(
        reportFixture(1),
        'Nov 2026',
        search: 'needle\r\n=1+1',
      ),
    );
    expect(text, contains('# Pencarian: needle =1+1'));
    expect(text, isNot(contains('\n=1+1')));
  });

  // ── A1-08: share result contract ─────────────────────────────────────

  test('dismissed share sheet returns cancelled, not success', () async {
    // Platform melaporkan user menutup sheet tanpa memilih tujuan.
    // share_plus v10: empty string '' adalah penanda dismissed di MethodChannelShare.
    messenger.setMockMethodCallHandler(sharing, (call) async {
      shares.add(call);
      return ''; // empty string → ShareResultStatus.dismissed
    });
    final result = await CsvExporter.export(
      transactions: reportFixture(),
      periodLabel: 'Nov 2026',
    );
    expect(
      result.isCancelled,
      isTrue,
      reason: 'dismissed share sheet must not be reported as success',
    );
    expect(result.isSuccess, isFalse);
    expect(shares, hasLength(1));
  });

  test(
    'unavailable share result is not claimed as success or failure',
    () async {
      // Platform tidak mendukung konfirmasi aksi — raw value khusus.
      messenger.setMockMethodCallHandler(sharing, (call) async {
        shares.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      final result = await CsvExporter.export(
        transactions: reportFixture(),
        periodLabel: 'Nov 2026',
      );
      expect(
        result.isUnavailable,
        isTrue,
        reason: 'unavailable must map to its own variant, not success',
      );
      expect(
        result.isSuccess,
        isFalse,
        reason: 'must not claim user confirmed receipt',
      );
      expect(
        result.isFailure,
        isFalse,
        reason: 'unavailable is not a technical failure',
      );
      expect(shares, hasLength(1));
    },
  );

  test(
    'success share result is not confused with unavailable or cancelled',
    () async {
      // Platform melaporkan user memilih tujuan — raw berisi identifier target.
      messenger.setMockMethodCallHandler(sharing, (call) async {
        shares.add(call);
        return 'com.example.target'; // non-empty, non-special raw → success
      });
      final result = await CsvExporter.export(
        transactions: reportFixture(),
        periodLabel: 'Nov 2026',
      );
      expect(
        result.isSuccess,
        isTrue,
        reason: 'explicit target selection must map to success',
      );
      expect(result.isCancelled, isFalse);
      expect(result.isUnavailable, isFalse);
      expect(shares, hasLength(1));
    },
  );
}
