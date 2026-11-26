import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import '../models/record_version.dart';
import '../models/sync_failure.dart';
import 'record_concurrency.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> loadOrCreate(String uid, String email);
  Future<UserProfile> save(
    String uid,
    UserProfile profile, {
    required UserProfile previous,
  });
}

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(FirebaseFirestore database)
    : _database = (() => database);
  FirestoreProfileRepository.lazy(this._database);
  final FirebaseFirestore Function() _database;

  DocumentReference<Map<String, dynamic>> _ref(String uid) {
    if (uid.isEmpty || uid.contains('/')) {
      throw ArgumentError('UID tidak valid.');
    }
    return _database().collection('users').doc(uid);
  }

  @override
  Future<UserProfile> loadOrCreate(String uid, String email) async {
    final ref = _ref(uid);
    await _database().runTransaction((transaction) async {
      final document = await transaction.get(ref);
      if (document.exists) return;
      final profile = UserProfile.initial(email);
      transaction.set(ref, {
        ...profile.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'revision': 1,
      });
    });
    return _confirmed(ref);
  }

  Future<UserProfile> _confirmed(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final document = await ref.get(const GetOptions(source: Source.server));
    if (!document.exists) throw const RecordConflict(ConflictReason.deleted);
    final data = document.data()!;
    final version = RecordConcurrency.read(data);
    if (version == null) {
      throw const FormatException('Metadata profil belum valid.');
    }
    return UserProfile.fromMap(data, version: version);
  }

  @override
  Future<UserProfile> save(
    String uid,
    UserProfile profile, {
    required UserProfile previous,
  }) async {
    final ref = _ref(uid);
    await _database().runTransaction((operation) async {
      final document = await operation.get(ref);
      if (!document.exists) throw const RecordConflict(ConflictReason.deleted);
      final data = document.data()!;
      final current = UserProfile.fromMap(data);
      final actual = RecordConcurrency.read(data);
      final changes = RecordConcurrency.profilePatch(
        before: previous.toMap(),
        desired: profile.toMap(),
        current: current.toMap(),
        expected: previous.version,
        actual: actual,
      );
      if (changes.isEmpty) return;
      operation.update(ref, {
        ...changes,
        'revision': RecordConcurrency.next(actual!),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    try {
      return await _confirmed(ref);
    } on RecordConflict {
      rethrow;
    } catch (error) {
      // The transaction already returned; a failed read is not a rejected write.
      throw SyncFailure.from(error, forceUnconfirmed: true);
    }
  }
}
