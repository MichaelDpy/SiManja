import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Meminta autentikasi ulang untuk satu [SensitiveOperation].
///
/// Mengembalikan [ReauthGrant] yang terikat pada UID sesi dan operasi itu,
/// atau `null` bila pengguna membatalkan. Operasi sensitif hanya boleh
/// dijalankan setelah grant diterima.
///
/// Akun tanpa provider password (mis. Google) tidak diminta password; dialog
/// menjelaskan bahwa verifikasi lewat provider tersebut belum tersedia (B06).
Future<ReauthGrant?> showReauthDialog(
  BuildContext context, {
  required AuthGateway auth,
  required SensitiveOperation operation,
}) => showDialog<ReauthGrant>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ReauthDialog(auth: auth, operation: operation),
);

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.auth, required this.operation});
  final AuthGateway auth;
  final SensitiveOperation operation;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final uid = widget.auth.currentUser?.uid;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grant = await widget.auth.reauthenticateWithPassword(
        _password.text,
        widget.operation,
      );
      if (!mounted) return;
      // Grant untuk UID yang sudah berganti tidak boleh dipakai.
      if (uid == null || grant.uid != uid) {
        setState(
          () => _error = authErrorMessage(
            FirebaseAuthException(code: 'user-mismatch'),
          ),
        );
        return;
      }
      Navigator.of(context).pop(grant);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;
    final passwordAccount = user?.hasPasswordProvider ?? false;
    return AlertDialog(
      title: const Text('Verifikasi ulang'),
      content: SingleChildScrollView(
        child: passwordAccount
            ? Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Demi keamanan, masukkan password akun '
                      '${user!.email} sebelum ${widget.operation.label}.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('reauth-password'),
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofocus: true,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Password wajib diisi'
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Password saat ini',
                        suffixIcon: IconButton(
                          tooltip: _obscure
                              ? 'Tampilkan password'
                              : 'Sembunyikan password',
                          onPressed: _busy
                              ? null
                              : () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const Key('reauth-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : Text(
                user == null
                    ? 'Sesi berakhir. Silakan masuk kembali.'
                    : 'Akun ini tidak memakai password, sehingga verifikasi '
                          'ulang harus lewat metode masuk akun tersebut. Fitur '
                          'itu belum tersedia.',
                key: const Key('reauth-unsupported'),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('reauth-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        if (passwordAccount)
          FilledButton(
            key: const Key('reauth-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Memeriksa…' : 'Lanjutkan'),
          ),
      ],
    );
  }
}
