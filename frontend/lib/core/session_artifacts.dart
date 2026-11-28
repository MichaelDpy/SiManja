import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Owns only SIMANJA export files. Never removes photos or arbitrary temp data.
class SessionExportStore {
  SessionExportStore({Future<Directory> Function()? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static SessionExportStore _instance = SessionExportStore();
  static SessionExportStore get instance => _instance;
  @visibleForTesting
  static void useForTesting(SessionExportStore store) => _instance = store;

  final Future<Directory> Function() _temporaryDirectory;
  Future<Directory>? _ready;
  SessionExportLease newLease() => SessionExportLease._(this);

  Future<Directory> prepare() => _ready ??= _prepare();

  Future<Directory> _prepare() async {
    try {
      final temp = await _temporaryDirectory();
      final root = Directory(
        '${temp.path}${Platform.pathSeparator}simanja_exports',
      );
      final type = await FileSystemEntity.type(root.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException('Direktori ekspor tidak tersedia.');
      }
      await root.create();
      await for (final item in root.list(followLinks: false)) {
        if (item is Directory && _ownedDirectory(root, item)) {
          await item.delete(recursive: true);
        }
      }
      // Exact C07 generated filename shape; never sweep all temp/CSV files.
      final previousFormat = RegExp(
        r'^simanja_transaksi_[A-Za-z0-9_-]+_[0-9]{10,}_[0-9]+\.csv$',
      );
      await for (final item in temp.list(followLinks: false)) {
        if (item is File && previousFormat.hasMatch(_name(item))) {
          await item.delete();
        }
      }
      return root;
    } catch (_) {
      _ready =
          null; // A later export may retry preparation; no unsafe fallback.
      rethrow;
    }
  }

  static String _name(FileSystemEntity item) =>
      item.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
  static bool _ownedDirectory(Directory root, Directory child) =>
      child.parent.absolute.uri.normalizePath() ==
          root.absolute.uri.normalizePath() &&
      _name(child).startsWith('csv-');

  Future<void> _remove(Directory root, Directory child) async {
    if (!_ownedDirectory(root, child)) {
      throw StateError('Path ekspor di luar store.');
    }
    final type = await FileSystemEntity.type(child.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw StateError('Path ekspor berubah.');
    }
    await child.delete(recursive: true);
  }
}

class SessionExportLease {
  SessionExportLease._(this._store);
  final SessionExportStore _store;
  final _directories = <String, ({Directory root, Directory child})>{};
  bool _active = true;
  bool get isActive => _active;

  Future<File?> write(
    List<int> bytes,
    String filename, {
    bool Function()? isCurrent,
  }) async {
    bool current() => _active && (isCurrent?.call() ?? true);
    if (!current()) return null;
    if (filename.contains('/') ||
        filename.contains('\\') ||
        !filename.endsWith('.csv')) {
      throw ArgumentError('Nama berkas ekspor tidak valid.');
    }
    final root = await _store.prepare();
    if (!current()) return null;
    final child = await root.createTemp('csv-');
    _directories[child.path] = (root: root, child: child);
    if (!current()) {
      await _discardDirectory(child.path);
      return null;
    }
    final file = File('${child.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    if (!current()) {
      await _discardDirectory(child.path);
      return null;
    }
    return file;
  }

  Future<void> discard(File file) => _discardDirectory(file.parent.path);

  Future<void> _discardDirectory(String path) async {
    final entry = _directories[path];
    if (entry == null) return;
    await _store._remove(entry.root, entry.child);
    _directories.remove(path);
  }

  /// Invalidates synchronously; cleanup is best-effort and never a cloud delete.
  Future<bool> retire() async {
    _active = false;
    var complete = true;
    for (final path in _directories.keys.toList()) {
      try {
        await _discardDirectory(path);
      } catch (_) {
        complete = false;
      }
    }
    return complete;
  }
}
