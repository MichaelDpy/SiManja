import 'package:flutter/material.dart';

import '../core/firebase_bootstrap.dart';
import '../services/auth_service.dart';

class AuthFormPage extends StatefulWidget {
  const AuthFormPage({super.key, required this.register, this.auth});
  final bool register;
  final AuthGateway? auth;
  @override
  State<AuthFormPage> createState() => _AuthFormPageState();
}

class _AuthFormPageState extends State<AuthFormPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  bool _success = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
      _success = false;
    });
    try {
      final auth = widget.auth ?? AuthService.instance;
      if (widget.register) {
        await auth.signUp(_email.text, _password.text);
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        }
      } else {
        await auth.resetPassword(_email.text);
        if (mounted) {
          setState(() {
            _success = true;
            _message = FirebaseBootstrap.useEmulators
                ? 'Permintaan pemulihan berhasil. Pada mode pengembangan, '
                      'tautan pemulihan tersedia di Auth Emulator.'
                : 'Jika email terdaftar, tautan pemulihan akan dikirim. '
                      'Periksa kotak masuk dan folder spam.';
          });
        }
      }
    } catch (error) {
      if (mounted) setState(() => _message = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.register ? 'Buat Akun' : 'Pulihkan Password'),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.register
                          ? 'Buat akun untuk mulai mencatat keuanganmu. Gunakan password yang kuat.'
                          : 'Masukkan email akun untuk meminta tautan pemulihan.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('auth-email'),
                      enabled: !_busy,
                      controller: _email,
                      validator: validateEmail,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: widget.register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: widget.register
                          ? null
                          : (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    if (widget.register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('auth-password'),
                        enabled: !_busy,
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) => v == null || v.isEmpty
                            ? 'Password wajib diisi'
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Tampilkan password'
                                : 'Sembunyikan password',
                            onPressed: _busy
                                ? null
                                : () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('auth-confirm'),
                        enabled: !_busy,
                        controller: _confirm,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v != _password.text
                            ? 'Konfirmasi password berbeda'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Konfirmasi Password',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_message != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          key: const Key('auth-result'),
                          style: TextStyle(
                            color: _success
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton(
                      key: const Key('auth-submit'),
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Memproses…'
                            : widget.register
                            ? 'Daftar'
                            : 'Kirim Tautan',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
