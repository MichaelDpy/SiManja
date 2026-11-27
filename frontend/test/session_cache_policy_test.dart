import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simanja/core/firestore_cache_policy.dart';

class SettingsRecorder extends Fake implements FirebaseFirestore {
  int writes = 0;
  Settings? configured;
  bool fail = false;
  @override
  set settings(Settings value) {
    writes++;
    if (fail) throw StateError('SDK already started');
    configured = value;
  }
}

void main() {
  test(
    'new client is memory-only exactly once without deleting persistence',
    () {
      final client = SettingsRecorder();
      FirestoreCachePolicy.configure(client);
      FirestoreCachePolicy.configure(client);
      expect(client.writes, 1);
      expect(client.configured!.persistenceEnabled, isFalse);
      // Unimplemented clearPersistence/terminate would throw from Fake.
    },
  );
  test('settings failure is not marked configured or silently ignored', () {
    final client = SettingsRecorder()..fail = true;
    expect(() => FirestoreCachePolicy.configure(client), throwsStateError);
    client.fail = false;
    FirestoreCachePolicy.configure(client);
    expect(client.writes, 2);
    expect(client.configured!.persistenceEnabled, isFalse);
  });
}
