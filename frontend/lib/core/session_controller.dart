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
    final previous = user;
    user = next;
    checking = false;
    error = null;
    if (next == null) {
      state.clearSession();
    } else if (previous?.uid != next.uid || previous?.email != next.email) {
      // userChanges juga memancar saat token/verifikasi berubah; data sesi
      // hanya dimulai ulang bila identitasnya benar-benar berubah.
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

  /// Memuat ulang status Auth (mis. setelah pengguna membuka tautan
  /// verifikasi). Hasil untuk UID lain atau sesi yang sudah berganti diabaikan.
  Future<SessionUser?> refreshUser() async {
    final before = user;
    if (_disposed || before == null) return before;
    final generation = _generation;
    final fresh = await auth.reloadUser();
    if (!_isCurrent(generation) || user?.uid != before.uid) return user;
    if (fresh != null && fresh.uid == before.uid && fresh != user) {
      user = fresh;
      notifyListeners();
    }
    return user;
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
