import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/session_artifacts.dart';

void main() {
  late Directory temp;
  late SessionExportStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('simanja-c08-artifacts-');
    store = SessionExportStore(temporaryDirectory: () async => temp);
  });
  tearDown(() async {
    expect(temp.parent.absolute.uri, Directory.systemTemp.absolute.uri);
    expect(
      temp.path.split(Platform.pathSeparator).last,
      startsWith('simanja-c08-artifacts-'),
    );
    await temp.delete(recursive: true);
  });

  test(
    'startup removes only recognized exports; unrelated files survive',
    () async {
      final root = await Directory('${temp.path}/simanja_exports').create();
      final old = await Directory('${root.path}/csv-old-process').create();
      await File('${old.path}/old.csv').writeAsString('old');
      final photo = await File('${temp.path}/photo.jpg')
          .writeAsString('source photo');
      final unrelated = await File('${root.path}/other.csv')
          .writeAsString('not managed');
      final legacy = await File(
        '${temp.path}/simanja_transaksi_Nov_1760000000000_0.csv',
      ).writeAsString('C07');
      await store.prepare();
      expect(await old.exists(), isFalse);
      expect(await legacy.exists(), isFalse);
      expect(await photo.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
      final lease = store.newLease();
      final file = await lease.write([1, 2], 'new.csv');
      await store.prepare();
      expect(
        await file!.exists(),
        isTrue,
      ); // no pruning of active process exports
      expect(await lease.retire(), isTrue);
      expect(await file.exists(), isFalse);
      expect(await photo.exists(), isTrue);
    },
  );

  test('retiring A cannot remove B files and invalidates before asynchronous cleanup', () async {
    final a = store.newLease();
    final b = store.newLease();
    final fileA = (await a.write([1], 'a.csv'))!;
    final fileB = (await b.write([2], 'b.csv'))!;
    final cleanup = a.retire();
    expect(a.isActive, isFalse);
    expect(await cleanup, isTrue);
    expect(await fileA.exists(), isFalse);
    expect(await fileB.exists(), isTrue);
    expect(await a.write([3], 'late.csv'), isNull);
    expect(await a.retire(), isTrue);
  });

  test(
    'lease retired while preparing directory never produces a late CSV',
    () async {
      final gate = Completer<Directory>();
      final delayedStore = SessionExportStore(
        temporaryDirectory: () => gate.future,
      );
      final lease = delayedStore.newLease();
      final writing = lease.write([1], 'late.csv');
      await lease.retire();
      gate.complete(temp);
      expect(await writing, isNull);
      expect(
        await temp.list(recursive: true).where((item) => item is File).toList(),
        isEmpty,
      );
    },
  );

  test(
    'failed preparation retries; no fallback outside managed root',
    () async {
      final blocked = File('${temp.path}/simanja_exports');
      await blocked.writeAsString('blocked');
      await expectLater(store.prepare(), throwsA(isA<FileSystemException>()));
      expect(await blocked.readAsString(), 'blocked');
      await blocked.delete();
      expect(
        await (await store.newLease().write([1], 'safe.csv'))!.exists(),
        isTrue,
      );
      await expectLater(
        store.newLease().write([1], '../photo.csv'),
        throwsArgumentError,
      );
    },
  );

  test('changed owned path fails cleanup honestly and is not deleted as an arbitrary file', () async {
    final lease = store.newLease();
    final file = (await lease.write([1], 'a.csv'))!;
    final ownDirectory = file.parent;
    await ownDirectory.delete(recursive: true);
    final replacement = await File(ownDirectory.path)
        .writeAsString('unexpected');
    expect(await lease.retire(), isFalse);
    expect(await replacement.readAsString(), 'unexpected');
  });

  test(
    'next process clears old managed exports without clearing any cloud data',
    () async {
      final old = (await store.newLease().write([1], 'old.csv'))!;
      final nextProcess = SessionExportStore(
        temporaryDirectory: () async => temp,
      );
      await nextProcess.prepare();
      expect(await old.exists(), isFalse);
    },
  );
}
