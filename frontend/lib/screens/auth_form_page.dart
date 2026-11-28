import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Email dari halaman login dibawa sekali sebagai nilai awal.
    if (_prefilled) return;
    _prefilled = true;
    final initial = ModalRoute.of(context)?.settings.arguments;
    if (initial is String && initial.isNotEmpty && _email.text.isEmpty) {
      _email.text = initial;
    }
  }

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
        // Kebijakan password project (bila dapat diambil) diperiksa sebelum
        // akun dibuat; server Auth tetap penentu akhir.
        final check = await auth.checkPassword(_password.text);
        if (!check.isValid) {
          if (mounted) {
            setState(() {
              _message =
                  'Password belum memenuhi kebijakan: '
                  '${check.unmet.join(', ')}.';
            });
          }
          return;
        }
        await auth.signUp(_email.text, _password.text);
        TextInput.finishAutofillContext();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
        }
      } else {
        await auth.resetPassword(_email.text);
        if (mounted) {
          setState(() {
            _success = true;
            // Pesan sama untuk email terdaftar maupun tidak (tanpa enumerasi).
            _message = FirebaseBootstrap.useEmulators
                ? 'Permintaan pemulihan diproses. Pada mode pengembangan, '
                      'tautan pemulihan tersedia di Auth Emulator, bukan '
                      'dikirim ke email sungguhan.'
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
                        validator: validateNewPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText:
                              'Minimal $firebaseMinPasswordLength karakter. '
                              'Kebijakan project dapat menambah syarat.',
                          helperMaxLines: 2,
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
                        // Password manager mengisi kedua kolom password baru.
                        autofillHints: const [AutofillHints.newPassword],
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
