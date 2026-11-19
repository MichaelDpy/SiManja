import 'dart:async';

import 'package:simanja/services/auth_service.dart';

class SessionAuth implements AuthGateway {
  SessionAuth({this.currentUser, this.emitInitial = true});
  SessionUser? currentUser;
  final bool emitInitial;
  final events = StreamController<SessionUser?>.broadcast(sync: true);
  Completer<void>? pendingSignOut;
  Object? signOutFailure;
  int signOutCalls = 0;
  bool emitSignOutEvent = true;

  @override
  Stream<SessionUser?> get authStateChanges => Stream.multi((sink) {
    if (emitInitial) sink.add(currentUser);
    final subscription = events.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
  });

  void emit(SessionUser? user) {
    currentUser = user;
    events.add(user);
  }

  @override
  Future<void> signIn(String email, String password) async =>
      emit(SessionUser(email.trim(), email.trim()));
  @override
  Future<void> signUp(String email, String password) => signIn(email, password);
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> signOut() async {
    signOutCalls++;
    await pendingSignOut?.future;
    if (signOutFailure != null) throw signOutFailure!;
    if (emitSignOutEvent) emit(null);
  }
}
