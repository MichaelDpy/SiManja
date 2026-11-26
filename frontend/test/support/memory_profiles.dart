import 'dart:async';

import 'package:simanja/models/user_profile.dart';
import 'package:simanja/models/record_version.dart';
import 'package:simanja/repositories/record_concurrency.dart';
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
    final profile = delayedLoads[uid] != null
        ? await delayedLoads[uid]!.future
        : profiles.putIfAbsent(uid, () => UserProfile.initial(email));
    return profiles[uid] = UserProfile.fromMap(
      profile.toMap(),
      version: profile.version ?? RecordVersion(0, 'memory:$uid', 'initial'),
    );
  }

  @override
  Future<UserProfile> save(
    String uid,
    UserProfile profile, {
    required UserProfile previous,
  }) async {
    final changes = profile.changesSince(previous);
    saves.add((uid: uid, changes: changes));
    await pendingSave?.future;
    if (saveFailure != null) throw saveFailure!;
    final current = profiles[uid];
    if (current == null) throw const RecordConflict(ConflictReason.deleted);
    final patch = RecordConcurrency.profilePatch(
      before: previous.toMap(),
      desired: profile.toMap(),
      current: current.toMap(),
      expected: previous.version,
      actual: current.version,
    );
    return profiles[uid] = UserProfile.fromMap(
      {...current.toMap(), ...patch},
      version: patch.isEmpty
          ? current.version
          : RecordVersion(
              current.version!.revision + 1,
              current.version!.createdAt,
              'save:${saves.length}',
            ),
    );
  }
}
