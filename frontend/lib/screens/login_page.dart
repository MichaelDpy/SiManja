import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.auth});
  final AuthGateway? auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _googleLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  AuthGateway get _auth => widget.auth ?? AuthService.instance;

  // Dipakai saat build: tidak boleh membuat instance Firebase.
  bool get _googleAvailable =>
      widget.auth?.googleSignInAvailable ?? AuthService.defaultGoogleAvailable;

  Future<void> _loginWithGoogle() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _googleLoading = true;
      _errorMessage = null;
    });
    try {
      await _auth.signInWithGoogle();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
    } on FirebaseAuthException catch (error) {
      // Batal memilih akun bukan kesalahan: tetap di halaman tanpa pesan.
      if (mounted && error.code != AuthErrorCodes.cancelled) {
        setState(() => _errorMessage = authErrorMessage(error));
      }
    } catch (error) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _googleLoading = false;
        });
      }
    }
  }

  Future<void> _login() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _auth.signIn(_emailCtrl.text, _passwordCtrl.text);
      // Beri tahu password manager bahwa kredensial berhasil dipakai.
      TextInput.finishAutofillContext();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      }
    } catch (error) {
      if (mounted) setState(() => _errorMessage = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Logo & Brand ─────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.teal,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'SIMANJA',
                        style: GoogleFonts.lato(
                          color: AppColors.teal,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sistem Manajemen Keuangan',
                        style: GoogleFonts.lato(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ── Judul ────────────────────────────────────────────────
                Text(
                  'Masuk ke Akun',
                  style: GoogleFonts.lato(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Masukkan email dan password untuk melanjutkan.',
                  style: GoogleFonts.lato(fontSize: 13, height: 1.5),
                ),

                const SizedBox(height: 28),

                // ── Form ─────────────────────────────────────────────────
                AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Email field
                        TextFormField(
                          key: const Key('login-email'),
                          enabled: !_isLoading,
                          autofillHints: const [AutofillHints.email],
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.lato(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'contoh@email.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: validateEmail,
                        ),

                        const SizedBox(height: 16),

                        // Password field
                        TextFormField(
                          key: const Key('login-password'),
                          enabled: !_isLoading,
                          autofillHints: const [AutofillHints.password],
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          style: GoogleFonts.lato(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Tampilkan password'
                                  : 'Sembunyikan password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      );
                                    },
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password wajib diisi';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Error message ─────────────────────────────────────────
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.expense.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.expense,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.lato(
                              color: AppColors.expense,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Tombol Login ──────────────────────────────────────────
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pushNamed(
                              context,
                              '/reset-password',
                              // Email yang sudah diketik ikut ke pemulihan.
                              arguments: _emailCtrl.text.trim(),
                            ),
                      child: const Text('Lupa password?'),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pushNamed(context, '/register'),
                      child: const Text('Buat akun'),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('login-submit'),
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.teal.withValues(
                        alpha: 0.38,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading && !_googleLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Masuk',
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                // Google hanya ditawarkan bila benar-benar terkonfigurasi.
                if (_googleAvailable) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('login-google'),
                      onPressed: _isLoading ? null : _loginWithGoogle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _googleLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.g_mobiledata, size: 28),
                      label: Text(
                        _googleLoading
                            ? 'Menghubungkan ke Google…'
                            : 'Masuk dengan Google',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
