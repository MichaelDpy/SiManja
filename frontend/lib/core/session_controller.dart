import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import 'app_state.dart';

/// Memeriksa sesi Auth tanpa bergantung pada Navigator atau widget.
class SessionController extends ChangeNotifier {
  SessionController(this.auth, {AppState? state})
    : state = state ?? AppState.instance {
    this.state.addListener(_stateChanged);
    _subscribe();
  }

  void _stateChanged() {
    if (!_disposed) notifyListeners();
  }

  final AuthGateway auth;
  final AppState state;
  StreamSubscription<SessionUser?>? _subscription;
  int _generation = 0;
  bool _disposed = false;
  SessionUser? user;
  bool checking = true;
  bool signingOut = false;
  String? error;

  void _subscribe() {
    final generation = ++_generation;
    _subscription?.cancel();
    checking = true;
    error = null;
    try {
      _subscription = auth.authStateChanges.listen(
        (next) => scheduleMicrotask(() => _receive(generation, next)),
        onError: (Object _) => scheduleMicrotask(() => _failed(generation)),
        onDone: () => scheduleMicrotask(() => _failed(generation)),
      );
    } catch (_) {
      scheduleMicrotask(() => _failed(generation));
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _receive(int generation, SessionUser? next) {
    if (!_isCurrent(generation)) return;
    user = next;
    checking = false;
    error = null;
    if (next == null) {
      state.clearSession();
    } else {
      unawaited(state.beginSession(next.uid, next.email));
    }
    notifyListeners();
  }

  void _failed(int generation) {
    if (!_isCurrent(generation)) return;
    user = null;
    checking = false;
    error = 'Sesi belum dapat diperiksa. Periksa koneksi lalu coba lagi.';
    state.clearSession();
    notifyListeners();
  }

  void retry() {
    if (_disposed || checking) return;
    _subscribe();
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_disposed || signingOut) return;
    final generation = _generation;
    final revision = state.sessionRevision;
    signingOut = true;
    notifyListeners();
    try {
      await auth.signOut();
      if (_isCurrent(generation) && state.sessionRevision == revision) {
        _receive(generation, null);
      }
    } finally {
      if (!_disposed) {
        signingOut = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    state.removeListener(_stateChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
