// Test-only SDK call recorder; these doubles never implement production I/O.
// Real SDK cursor behavior is covered by the emulator/native probes.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the production repository's SDK calls. Does not emulate query
/// execution; actual ordering, cursors and rules are tested against Firebase.
class RecordingFirestore extends Fake implements FirebaseFirestore {
  final calls = <Invocation>[];
  final paths = <String>[];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> documents = [];
  bool fromCache = false;
  bool pending = false;
  Object? failure;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    paths.add(collectionPath);
    return _Collection(this);
  }
}

class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.owner);
  final RecordingFirestore owner;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    owner.paths.add(path!);
    return _Document(owner);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    owner.calls.add(invocation);
    if (invocation.memberName == #get) {
      if (owner.failure case final error?) {
        return Future<QuerySnapshot<Map<String, dynamic>>>.error(error);
      }
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        _Snapshot(owner),
      );
    }
    if ([
      #where,
      #orderBy,
      #limit,
      #startAfter,
    ].contains(invocation.memberName)) {
      return this;
    }
    return super.noSuchMethod(invocation);
  }
}

class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.owner);
  final RecordingFirestore owner;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    owner.paths.add(collectionPath);
    return _Collection(owner);
  }
}

class RecordingDocument extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  RecordingDocument(this.id, this.fields, {bool pending = false})
    : metadata = _Metadata(false, pending);
  @override
  final String id;
  final Map<String, dynamic> fields;
  @override
  final SnapshotMetadata metadata;
  @override
  Map<String, dynamic> data() => fields;
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.owner);
  final RecordingFirestore owner;
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => owner.documents;
  @override
  SnapshotMetadata get metadata => _Metadata(owner.fromCache, owner.pending);
}

class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata(this.isFromCache, this.hasPendingWrites);
  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}
