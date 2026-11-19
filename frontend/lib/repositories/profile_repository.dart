import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> loadOrCreate(String uid, String email);
  Future<void> save(
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
    return _database().runTransaction((transaction) async {
      final document = await transaction.get(ref);
      if (document.exists) return UserProfile.fromMap(document.data()!);
      final profile = UserProfile.initial(email);
      transaction.set(ref, {
        ...profile.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return profile;
    });
  }

  @override
  Future<void> save(
    String uid,
    UserProfile profile, {
    required UserProfile previous,
  }) async {
    final ref = _ref(uid);
    final changes = profile.changesSince(previous);
    if (changes.isEmpty) return;
    await ref.update({...changes, 'updatedAt': FieldValue.serverTimestamp()});
  }
}
