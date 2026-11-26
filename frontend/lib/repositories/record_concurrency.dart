import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/record_version.dart';

abstract final class RecordConcurrency {
  static const maxRevision = 9007199254740991;
  static RecordVersion? read(Map<String, dynamic> data) {
    final revision = data['revision'] ?? 0;
    if ((data.containsKey('revision') && (revision is! int || revision < 1)) ||
        revision is! int ||
        revision > maxRevision) {
      throw const FormatException('Versi dokumen tidak valid.');
    }
    final created = data['createdAt'];
    final updated = data['updatedAt'];
    if (created is! Timestamp || updated is! Timestamp) return null;
    String token(Timestamp stamp) => '${stamp.seconds}:${stamp.nanoseconds}';
    return RecordVersion(revision, token(created), token(updated));
  }

  static int next(RecordVersion version) {
    if (version.revision >= maxRevision) {
      throw const RecordConflict(ConflictReason.exhausted);
    }
    return version.revision + 1;
  }

  static void requireSame(RecordVersion? expected, RecordVersion? actual) {
    if (expected == null || actual == null) {
      throw const RecordConflict(ConflictReason.unconfirmed);
    }
    if (expected != actual) throw const RecordConflict(ConflictReason.changed);
  }

  /// Only a pristine matching create, or exactly the next matching revision,
  /// can acknowledge a retry. Different data/incarnations remain conflicts.
  static bool confirmsRetry({
    required Map<String, Object> desired,
    required Map<String, dynamic> current,
    RecordVersion? expected,
  }) {
    final actual = read(current);
    if (actual == null) return false;
    final matching =
        current.containsKey('dateVersion') ==
            desired.containsKey('dateVersion') &&
        desired.entries.every(
          (entry) =>
              current[entry.key] == entry.value &&
              (entry.value is! int || current[entry.key] is int),
        );
    if (!matching) return false;
    if (expected == null) {
      return actual.revision == 1 && actual.createdAt == actual.updatedAt;
    }
    return actual.createdAt == expected.createdAt &&
        actual.revision == expected.revision + 1;
  }

  /// Profile policy: same incarnation, merge independent fields, reject a field
  /// changed to a different value. Equal desired values make retries harmless.
  static Map<String, Object> profilePatch({
    required Map<String, Object> before,
    required Map<String, Object> desired,
    required Map<String, Object> current,
    required RecordVersion? expected,
    required RecordVersion? actual,
  }) {
    if (expected == null || actual == null) {
      throw const RecordConflict(ConflictReason.unconfirmed);
    }
    if (expected.createdAt != actual.createdAt) {
      throw const RecordConflict(ConflictReason.changed);
    }
    final patch = <String, Object>{};
    for (final field in desired.keys) {
      if (desired[field] == before[field]) continue;
      if (current[field] != before[field] && current[field] != desired[field]) {
        throw const RecordConflict(ConflictReason.changed);
      }
      if (current[field] != desired[field]) patch[field] = desired[field]!;
    }
    return patch;
  }
}
