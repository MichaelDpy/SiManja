import 'dart:async';

import 'package:flutter/material.dart';

import '../core/firebase_bootstrap.dart';
import '../core/session_controller.dart';
import '../services/auth_service.dart';

/// Pengguna email/password yang belum terverifikasi menurut server Auth.
///
/// Kebijakan R00 tentang akses sebelum verifikasi masih OPEN, sehingga
/// verifikasi tidak memblokir aplikasi dan bukan kontrol keamanan (rules tidak
/// memeriksanya). Banner ini hanya menawarkan kirim/periksa ulang yang jujur.
bool needsEmailVerification(SessionUser? user) =>
    user != null &&
    user.hasPasswordProvider &&
    user.email.isNotEmpty &&
    !user.emailVerified;

class EmailVerificationBanner extends StatefulWidget {
  const EmailVerificationBanner({
    super.key,
    required this.session,
    this.cooldown = const Duration(seconds: 60),
  });

  final SessionController session;

  /// Jeda minimum antar-pengiriman agar tidak memicu batas kirim Firebase.
  final Duration cooldown;

  @override
  State<EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

enum _Tone { info, success, error }

class _EmailVerificationBannerState extends State<EmailVerificationBanner>
    with WidgetsBindingObserver {
  bool _sending = false;
  bool _checking = false;
  int _cooldownLeft = 0;
  Timer? _timer;
  String? _message;
  _Tone _tone = _Tone.info;
  DateTime? _lastAutoCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Kembali dari aplikasi email → periksa status otomatis (dibatasi).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (_lastAutoCheck != null &&
        now.difference(_lastAutoCheck!) < const Duration(seconds: 10)) {
      return;
    }
    _lastAutoCheck = now;
    unawaited(_check(silent: true));
  }

  void _show(String message, _Tone tone) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _tone = tone;
    });
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldownLeft = widget.cooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (_sending || _cooldownLeft > 0) return;
    final uid = widget.session.user?.uid;
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.session.auth.sendEmailVerification();
      if (!mounted || widget.session.user?.uid != uid) return;
      _startCooldown();
      _show(
        FirebaseBootstrap.useEmulators
            ? 'Tautan verifikasi dibuat di Auth Emulator (bukan email '
                  'sungguhan). Buka tautannya, lalu tekan Periksa.'
            : 'Tautan verifikasi dikirim ke ${widget.session.user?.email}. '
                  'Buka tautannya, lalu tekan Periksa.',
        _Tone.success,
      );
    } catch (error) {
      if (mounted && widget.session.user?.uid == uid) {
        _show(authErrorMessage(error), _Tone.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    final uid = widget.session.user?.uid;
    if (uid == null) return;
    setState(() {
      _checking = true;
      if (!silent) _message = null;
    });
    try {
      final fresh = await widget.session.refreshUser();
      if (!mounted || fresh?.uid != uid) return;
      if (fresh!.emailVerified) {
        _show('Email sudah terverifikasi.', _Tone.success);
      } else if (!silent) {
        _show(
          'Email belum terverifikasi. Pastikan tautan terbaru sudah dibuka.',
          _Tone.info,
        );
      }
    } catch (error) {
      if (mounted && !silent) _show(authErrorMessage(error), _Tone.error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = widget.session.user;
    final verified = user != null && user.emailVerified;
    final messageColor = switch (_tone) {
      _Tone.error => colors.error,
      _ => colors.onTertiaryContainer,
    };

    return Material(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    verified
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                    size: 20,
                    color: colors.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verified
                        ? 'Email terverifikasi.'
                        : 'Email ${user?.email ?? ''} belum diverifikasi.',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            // Firebase mencabut password yang belum terverifikasi bila email
            // yang sama kemudian dipakai login Google (terbukti di emulator).
            if (!verified && widget.session.auth.googleSignInAvailable)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(
                  'Verifikasi agar password tetap berlaku bila nanti Anda '
                  'masuk dengan Google memakai email yang sama.',
                  key: const Key('verify-google-note'),
                  style: TextStyle(
                    color: colors.onTertiaryContainer,
                    fontSize: 12,
                  ),
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    key: const Key('verify-message'),
                    style: TextStyle(color: messageColor, fontSize: 12),
                  ),
                ),
              ),
            if (!verified)
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      key: const Key('verify-send'),
                      onPressed: _sending || _cooldownLeft > 0 ? null : _send,
                      child: Text(
                        _sending
                            ? 'Mengirim…'
                            : _cooldownLeft > 0
                            ? 'Kirim ulang (${_cooldownLeft}d)'
                            : 'Kirim tautan',
                      ),
                    ),
                    TextButton(
                      key: const Key('verify-check'),
                      onPressed: _checking ? null : () => _check(),
                      child: Text(_checking ? 'Memeriksa…' : 'Periksa'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
