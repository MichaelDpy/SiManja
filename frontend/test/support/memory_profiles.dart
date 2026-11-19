import 'dart:async';

import 'package:simanja/models/user_profile.dart';
import 'package:simanja/repositories/profile_repository.dart';

class MemoryProfiles implements ProfileRepository {
  final profiles = <String, UserProfile>{};
  final delayedLoads = <String, Completer<UserProfile>>{};
  final saves = <({String uid, Map<String, Object> changes})>[];
  int loadCalls = 0;
  Object? loadFailure;
  Object? saveFailure;
  Completer<void>? pendingSave;

  @override
  Future<UserProfile> loadOrCreate(String uid, String email) async {
    loadCalls++;
    if (loadFailure != null) throw loadFailure!;
    if (delayedLoads[uid] case final request?) return request.future;
    return profiles.putIfAbsent(uid, () => UserProfile.initial(email));
  }

  @override
  Future<void> save(
    String uid,
    UserProfile profile, {
    required UserProfile previous,
  }) async {
    final changes = profile.changesSince(previous);
    saves.add((uid: uid, changes: changes));
    await pendingSave?.future;
    if (saveFailure != null) throw saveFailure!;
    profiles[uid] = UserProfile.fromMap({
      ...profiles[uid]!.toMap(),
      ...changes,
    });
  }
}
