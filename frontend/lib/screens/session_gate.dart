import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/session_controller.dart';
import '../core/firebase_bootstrap.dart';
import '../repositories/profile_repository.dart';
import '../repositories/transaction_repository.dart';
import '../widgets/email_verification_banner.dart';
import '../widgets/transaction_sync_status.dart';
import '../services/auth_service.dart';
import '../widgets/session_scope.dart';
import 'intro_page.dart';
import 'login_page.dart';
import 'main_shell.dart';

class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    this.auth,
    this.state,
    this.showIntroWhenSignedOut = false,
    this.homeBuilder,
    this.profiles,
    this.transactions,
  });
  final AuthGateway? auth;
  final AppState? state;
  final bool showIntroWhenSignedOut;
  final WidgetBuilder? homeBuilder;
  final ProfileRepository? profiles;
  final TransactionRepository? transactions;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  SessionController? _session;
  String? _lastUid;
  bool _navigationQueued = false;

  @override
  void initState() {
    super.initState();
    try {
      final state = widget.state ?? AppState.instance;
      if (widget.transactions != null) {
        state.useTransactionRepository(widget.transactions!);
      } else if (!state.hasTransactionRepository) {
        state.useTransactionRepository(
          FirestoreTransactionRepository.lazy(
            () => FirebaseBootstrap.firestore,
          ),
        );
      }
      if (widget.profiles != null) {
        state.useProfileRepository(widget.profiles!);
      } else if (!state.hasProfileRepository) {
        state.useProfileRepository(
          FirestoreProfileRepository.lazy(() => FirebaseBootstrap.firestore),
        );
      }
      _session = SessionController(
        widget.auth ?? AuthService.instance,
        state: state,
      )..addListener(_changed);
    } catch (_) {
      // Route langsung sebelum bootstrap tidak boleh membuka Home.
    }
  }

  void _changed() {
    if (!mounted) return;
    final nextUid = _session!.user?.uid;
    if (_lastUid != null && _lastUid != nextUid && !_navigationQueued) {
      _navigationQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigationQueued = false;
        // Tutup juga dialog/form yang masih membawa data UID sebelumnya.
        final target = _session!.user == null ? '/login' : '/home';
        Navigator.of(context).pushNamedAndRemoveUntil(target, (_) => false);
      });
    }
    _lastUid = nextUid;
    setState(() {});
  }

  Future<void> _signOut() async {
    try {
      await _session!.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal keluar. Silakan coba lagi.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_changed);
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (_) => false),
              child: const Text('Siapkan Firebase terlebih dahulu'),
            ),
          ),
        ),
      );
    }
    if (session.checking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Memeriksa sesi…'),
            ],
          ),
        ),
      );
    }
    if (session.error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(session.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: session.retry,
                    child: const Text('Coba lagi'),
                  ),
                  TextButton(
                    onPressed: session.signingOut ? null : _signOut,
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (session.user == null) {
      return widget.showIntroWhenSignedOut
          ? const IntroPage()
          : LoginPage(auth: session.auth);
    }
    final state = session.state;
    if (state.profileLoading) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Memuat profil…'),
                TextButton(
                  onPressed: session.signingOut ? null : _signOut,
                  child: const Text('Keluar'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (state.profileError != null || !state.profileReady) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.profileError ?? 'Profil belum siap.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.retryProfile,
                    child: const Text('Muat ulang profil'),
                  ),
                  TextButton(
                    onPressed: session.signingOut ? null : _signOut,
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final uid = session.user!.uid;
    final syncVisible = state.hasTransactionNotice;
    final verifyVisible = needsEmailVerification(session.user);
    final noticesVisible = syncVisible || verifyVisible;
    return SessionScope(
      controller: session,
      child: Column(
        children: [
          // Pemberitahuan atas berbagi satu safe area. Saat tampil, padding
          // atas halaman di bawahnya dihapus agar tidak ada jarak ganda;
          // struktur pohon tetap sama sehingga state tab tidak hilang.
          if (noticesVisible)
            SafeArea(
              bottom: false,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (syncVisible) TransactionSyncStatus(state: state),
                    if (verifyVisible)
                      EmailVerificationBanner(
                        key: ValueKey('verify-$uid'),
                        session: session,
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            key: const ValueKey('session-body'),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: noticesVisible,
              child: KeyedSubtree(
                key: ValueKey(uid),
                child: widget.homeBuilder == null
                    ? const MainShell()
                    : Builder(builder: widget.homeBuilder!),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
