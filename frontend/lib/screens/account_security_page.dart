import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import 'reauth_dialog.dart';

/// Pusat keamanan akun. Semua data berasal dari Firebase Auth (bukan profil
/// Firestore). Pintu masuk dari Profil dipasang A17 melalui route
/// `/account-security`.
class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key, this.auth});
  final AuthGateway? auth;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  late final AuthGateway _auth = widget.auth ?? AuthService.instance;
  SessionUser? _user;
  bool _refreshing = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
  }

  Future<void> _refresh() async {
    if (_refreshing || _user == null) return;
    final uid = _user!.uid;
    setState(() {
      _refreshing = true;
      _message = null;
    });
    try {
      final fresh = await _auth.reloadUser();
      if (!mounted) return;
      setState(() => _user = fresh?.uid == uid ? fresh : null);
    } catch (error) {
      if (mounted) setState(() => _message = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChangePasswordSheet(auth: _auth),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password berhasil diganti untuk akun ini.'),
        ),
      );
    }
  }

  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Menjalankan operasi sensitif: reauth → aksi → muat ulang status.
  /// Batal/gagal tidak menjalankan aksi dan tidak menampilkan sukses.
  Future<void> _sensitive(
    SensitiveOperation operation,
    Future<void> Function(ReauthGrant grant) action,
    String success,
  ) async {
    if (_busy) return;
    final uid = _user?.uid;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final grant = await showReauthDialog(
        context,
        auth: _auth,
        operation: operation,
      );
      if (!mounted || grant == null) return;
      await action(grant);
      final fresh = await _auth.reloadUser();
      if (!mounted) return;
      setState(() => _user = fresh?.uid == uid ? fresh : null);
      _snack(success);
    } on FirebaseAuthException catch (error) {
      if (mounted && error.code != AuthErrorCodes.cancelled) {
        setState(() => _message = authErrorMessage(error));
      }
    } catch (error) {
      if (mounted) setState(() => _message = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkGoogle() => _sensitive(
    SensitiveOperation.linkProvider,
    _auth.linkGoogle,
    'Google terhubung ke akun ini. Data akun tetap sama.',
  );

  Future<void> _linkPassword() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewPasswordSheet(auth: _auth),
    );
    if (password == null || !mounted) return;
    await _sensitive(
      SensitiveOperation.linkProvider,
      (grant) => _auth.linkPassword(grant, password),
      'Password ditambahkan. Kini Anda bisa masuk dengan email dan password.',
    );
  }

  Future<void> _unlink(String providerId) async {
    final user = _user;
    if (user == null) return;
    // Cek lokal lebih dulu agar pengguna tidak diminta reauth sia-sia.
    final reason = unlinkBlockReason(
      user.providerIds,
      providerId,
      googleAvailable: _auth.googleSignInAvailable,
    );
    if (reason != null) {
      setState(() => _message = reason);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Lepas ${providerLabel(providerId)}?'),
        content: Text(
          'Anda tidak bisa lagi masuk dengan ${providerLabel(providerId)}. '
          'Metode lain tetap dapat dipakai dan data akun tidak berubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            key: const Key('unlink-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lepas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _sensitive(
      SensitiveOperation.unlinkProvider,
      (grant) => _auth.unlinkProvider(grant, providerId),
      '${providerLabel(providerId)} dilepas dari akun ini.',
    );
  }

  static String providerLabel(String id) => switch (id) {
    'password' => 'Email & password',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    'phone' => 'Nomor telepon',
    _ => id,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Keamanan Akun')),
      body: SafeArea(
        child: user == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Sesi berakhir. Silakan masuk kembali.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context)
                            .pushNamedAndRemoveUntil('/login', (_) => false),
                        child: const Text('Masuk'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: const Text('Email identitas'),
                    subtitle: Text(user.email.isEmpty ? '—' : user.email),
                  ),
                  ListTile(
                    key: const Key('security-verified'),
                    leading: Icon(
                      user.emailVerified
                          ? Icons.verified_outlined
                          : Icons.mark_email_unread_outlined,
                    ),
                    title: Text(
                      user.emailVerified
                          ? 'Email terverifikasi'
                          : 'Email belum diverifikasi',
                    ),
                    subtitle: const Text('Status dari server Firebase Auth'),
                    trailing: IconButton(
                      key: const Key('security-refresh'),
                      tooltip: 'Muat ulang status',
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Metode masuk'),
                    subtitle: Text(
                      user.providerIds.isEmpty
                          ? '—'
                          : user.providerIds.map(providerLabel).join(', '),
                      key: const Key('security-providers'),
                    ),
                  ),
                  if (user.lastSignInTime != null)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('Masuk terakhir'),
                      subtitle: Text(
                        DateFormat(
                          'd MMMM yyyy, HH:mm',
                          'id_ID',
                        ).format(user.lastSignInTime!.toLocal()),
                      ),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        _message!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      'Kelola metode masuk',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final id in user.providerIds)
                    ListTile(
                      key: Key('provider-$id'),
                      leading: Icon(
                        id == googleProviderId
                            ? Icons.g_mobiledata
                            : Icons.password,
                      ),
                      title: Text(providerLabel(id)),
                      subtitle: const Text('Terhubung'),
                      trailing: user.providerIds.length > 1
                          ? TextButton(
                              key: Key('unlink-$id'),
                              onPressed: _busy ? null : () => _unlink(id),
                              child: const Text('Lepas'),
                            )
                          : null,
                    ),
                  if (!user.providerIds.contains(googleProviderId))
                    _auth.googleSignInAvailable
                        ? ListTile(
                            key: const Key('link-google'),
                            leading: const Icon(Icons.add_link),
                            title: const Text('Hubungkan Google'),
                            subtitle: const Text(
                              'Masuk ke akun yang sama dengan Google',
                            ),
                            enabled: !_busy,
                            onTap: _linkGoogle,
                          )
                        : const ListTile(
                            key: Key('google-unavailable'),
                            leading: Icon(Icons.link_off),
                            title: Text('Google belum tersedia'),
                            subtitle: Text(
                              'Login Google belum dikonfigurasi untuk '
                              'aplikasi ini.',
                            ),
                            enabled: false,
                          ),
                  if (!user.hasPasswordProvider && user.email.isNotEmpty)
                    ListTile(
                      key: const Key('link-password'),
                      leading: const Icon(Icons.add_link),
                      title: const Text('Tambah password'),
                      subtitle: const Text(
                        'Cadangan agar tetap bisa masuk tanpa Google',
                      ),
                      enabled: !_busy,
                      onTap: _linkPassword,
                    ),
                  const Divider(height: 24),
                  if (user.hasPasswordProvider)
                    ListTile(
                      key: const Key('security-change-password'),
                      leading: const Icon(Icons.password),
                      title: const Text('Ganti password'),
                      subtitle: const Text(
                        'Memerlukan password saat ini untuk verifikasi ulang',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePassword,
                    )
                  else
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Ganti password tidak tersedia'),
                      subtitle: Text(
                        'Akun ini masuk tanpa password. Kelola keamanannya '
                        'melalui penyedia metode masuk tersebut.',
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.auth});
  final AuthGateway auth;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _form = GlobalKey<FormState>();
  final _newPassword = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final check = await widget.auth.checkPassword(_newPassword.text);
      if (!mounted) return;
      if (!check.isValid) {
        setState(
          () => _error =
              'Password baru belum memenuhi kebijakan: '
              '${check.unmet.join(', ')}.',
        );
        return;
      }
      final grant = await showReauthDialog(
        context,
        auth: widget.auth,
        operation: SensitiveOperation.changePassword,
      );
      if (!mounted) return;
      if (grant == null) {
        setState(() => _error = 'Dibatalkan. Password tidak diubah.');
        return;
      }
      await widget.auth.changePassword(grant, _newPassword.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ganti password',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('change-new'),
                  controller: _newPassword,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: validateNewPassword,
                  decoration: InputDecoration(
                    labelText: 'Password baru',
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
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('change-confirm'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) => v != _newPassword.text
                      ? 'Konfirmasi password berbeda'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi password baru',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const Key('change-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('change-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Memproses…' : 'Simpan password baru'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Meminta password baru (untuk menambahkan password ke akun Google).
/// Mengembalikan password bila valid; reauth dan link dilakukan pemanggil.
class _NewPasswordSheet extends StatefulWidget {
  const _NewPasswordSheet({required this.auth});
  final AuthGateway auth;

  @override
  State<_NewPasswordSheet> createState() => _NewPasswordSheetState();
}

class _NewPasswordSheetState extends State<_NewPasswordSheet> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final check = await widget.auth.checkPassword(_password.text);
      if (!mounted) return;
      if (!check.isValid) {
        setState(
          () => _error =
              'Password belum memenuhi kebijakan: ${check.unmet.join(', ')}.',
        );
        return;
      }
      Navigator.of(context).pop(_password.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tambah password',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('link-password-new'),
                controller: _password,
                obscureText: true,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                validator: validateNewPassword,
                decoration: const InputDecoration(labelText: 'Password baru'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('link-password-confirm'),
                controller: _confirm,
                obscureText: true,
                enabled: !_busy,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    v != _password.text ? 'Konfirmasi password berbeda' : null,
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi password',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('link-password-submit'),
                onPressed: _busy ? null : _submit,
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
