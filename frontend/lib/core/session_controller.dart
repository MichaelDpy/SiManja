import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import 'app_state.dart';

/// Memeriksa sesi Auth tanpa bergantung pada Navigator atau widget.
class SessionController extends ChangeNotifier {
  SessionController(this.auth, {AppState? state})
    : state = state ?? AppState.instance {
    _subscribe();
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
    if (next == null) {
      state.clearSession();
    } else {
      state.beginSession(next.uid, next.email);
    }
    user = next;
    checking = false;
    error = null;
    notifyListeners();
  }

  void _failed(int generation) {
    if (!_isCurrent(generation)) return;
    state.clearSession();
    user = null;
    checking = false;
    error = 'Sesi belum dapat diperiksa. Periksa koneksi lalu coba lagi.';
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
    _subscription?.cancel();
    super.dispose();
  }
}
