import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../models/record_version.dart';
import '../models/sync_failure.dart';
import '../services/auth_service.dart';
import '../widgets/local_avatar.dart';
import '../widgets/session_scope.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

/// Keadaan editor profil untuk jalur keluar (A1-10).
///
/// - [clean]: tidak ada perubahan terhadap baseline → keluar tanpa discard.
/// - [dirty]: ada perubahan belum disimpan → keputusan discard eksplisit.
/// - [saving]: sedang menyimpan → state sementara, di-reset di `finally`
///   (ada jalur keluar; tidak menjebak); preferensi & form tidak ditumpuk.
///
/// CATATAN: ini BUKAN penjebak navigasi. Tidak ada `PopScope`; pindah tab
/// sendiri tetap dipertahankan via `IndexedStack` di `MainShell`.
enum ProfileFormState { clean, dirty, saving }

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _namaCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _waCtrl;
  late final TextEditingController _alamatCtrl;
  late final TextEditingController _kotaCtrl;
  late final TextEditingController _pekerjaanCtrl;
  late final TextEditingController _pendapatanCtrl;

  bool _isSaving = false;
  bool _isLoggingOut = false;
  String? _saveError;

  /// Baseline = profil terakhir yang terkonfirmasi/tersimpan (atau snapshot
  /// awal). Dirty dihitung terhadap baseline ini; diperbarui pada success.
  late UserProfile _editBase;

  // A1-10: dirty tracking.
  bool _isDirty = false;

  /// Field form yang dapat diedit (email identitas read-only, tidak dirty).
  List<TextEditingController> get _dirtyControllers => [
    _namaCtrl,
    _waCtrl,
    _alamatCtrl,
    _kotaCtrl,
    _pekerjaanCtrl,
    _pendapatanCtrl,
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    _editBase = s.profileSnapshot;
    _namaCtrl = TextEditingController(text: s.name);
    _emailCtrl = TextEditingController(text: s.email);
    _waCtrl = TextEditingController(text: s.phone);
    _alamatCtrl = TextEditingController(text: s.address);
    _kotaCtrl = TextEditingController(text: s.city);
    _pekerjaanCtrl = TextEditingController(text: s.job);
    // Tampilkan angka bulat tanpa separator saat edit
    // A1-03: pendapatan nol dipertahankan ('0', bukan dikosongkan); kosong→0.
    _pendapatanCtrl = TextEditingController(
      text: s.monthlyIncome.toInt().toString(),
    );
    for (final c in _dirtyControllers) {
      c.addListener(_onFieldChanged);
    }
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    for (final c in _dirtyControllers) {
      c.removeListener(_onFieldChanged);
    }
    _namaCtrl.dispose();
    _emailCtrl.dispose();
    _waCtrl.dispose();
    _alamatCtrl.dispose();
    _kotaCtrl.dispose();
    _pekerjaanCtrl.dispose();
    _pendapatanCtrl.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // ── Dirty state (A1-10) ───────────────────────────────────────────────

  void _onFieldChanged() => _updateDirty();

  void _updateDirty() {
    final dirty = _checkDirty();
    if (dirty != _isDirty && mounted) setState(() => _isDirty = dirty);
  }

  /// Periksa apakah form berbeda dari baseline (`_editBase`).
  /// Perbandingan SEMANTIK, bukan teks mentah: trim nama/telepon/alamat/kota/
  /// pekerjaan; pendapatan dibanding nilai rupiah bulat (`parseIncome`,
  /// kosong→0; invalid→dirty). Email read-only tidak ikut.
  bool _checkDirty() {
    final b = _editBase;
    if (_namaCtrl.text.trim() != b.name.trim()) return true;
    if (_waCtrl.text.trim() != b.phone.trim()) return true;
    if (_alamatCtrl.text.trim() != b.address.trim()) return true;
    if (_kotaCtrl.text.trim() != b.city.trim()) return true;
    if (_pekerjaanCtrl.text.trim() != b.job.trim()) return true;
    final raw = _pendapatanCtrl.text.trim();
    final parsed = raw.isEmpty ? 0.0 : UserProfile.parseIncome(raw);
    if (parsed == null) return true; // invalid pendapatan → draft berbeda
    return parsed != b.monthlyIncome;
  }

  /// Keadaan form untuk jalur keluar (A1-10).
  ///
  /// `dirty` didahulukan agar keputusan discard tidak hilang karena ada juga
  /// `saving`; `saving` di-reset di `finally` (`_isSaving`) → jalur keluar.
  ProfileFormState get _formState {
    if (_isDirty) return ProfileFormState.dirty;
    if (_isSaving || AppState.instance.profileSaving) {
      return ProfileFormState.saving;
    }
    return ProfileFormState.clean;
  }

  // ── Foto ──────────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PhotoPickerSheet(
        hasPhoto: AppState.instance.photoPath != null,
        onCamera: () => _pickFromSource(ImageSource.camera),
        onGallery: () => _pickFromSource(ImageSource.gallery),
        onDelete: _deletePhoto,
      ),
    );
  }

  Future<void> _pickFromSource(ImageSource source) async {
    final sessionRevision = AppState.instance.sessionRevision;
    // Tutup sheet dulu
    if (mounted) Navigator.pop(context);

    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );

      // null = pengguna membatalkan — tidak ada aksi
      if (img == null) return;

      // Verifikasi file benar-benar ada sebelum menyimpan path
      final file = File(img.path);
      if (!await file.exists()) {
        if (mounted) _showPhotoError('File foto tidak ditemukan');
        return;
      }

      if (!mounted || AppState.instance.sessionRevision != sessionRevision) {
        return;
      }
      AppState.instance.updatePhoto(img.path);
    } on PlatformException catch (e) {
      if (!mounted) return;
      // Kode 'photo_access_denied' dan 'camera_access_denied' dari image_picker
      if (e.code.contains('access_denied') ||
          e.code.contains('permission') ||
          e.code == 'photo_access_denied' ||
          e.code == 'camera_access_denied') {
        _showPhotoError(
          'Izin ${source == ImageSource.camera ? 'kamera' : 'galeri'} '
          'ditolak. Buka Pengaturan untuk mengizinkan akses.',
        );
      } else {
        _showPhotoError('Gagal memilih foto: ${e.message}');
      }
    } catch (e) {
      if (mounted) _showPhotoError('Gagal memilih foto: $e');
    }
  }

  void _deletePhoto() {
    if (mounted) Navigator.pop(context);
    AppState.instance.updatePhoto('');
  }

  void _showPhotoError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.lato(color: Colors.white)),
        backgroundColor: AppColors.expense,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Simpan ────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isSaving || AppState.instance.profileSaving) return;
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;

    // Validasi pendapatan
    final income = UserProfile.parseIncome(_pendapatanCtrl.text);
    if (_pendapatanCtrl.text.trim().isNotEmpty && income == null) {
      setState(
        () => _saveError =
            // A1-03: pesan selaras validator field & kontrak domain.
            'Pendapatan harus berupa angka bulat non-negatif',
      );
      return;
    }

    setState(() => _isSaving = true);
    final submitted = _editBase.copyWith(
      name: _namaCtrl.text.trim(),
      phone: _waCtrl.text.trim(),
      address: _alamatCtrl.text.trim(),
      city: _kotaCtrl.text.trim(),
      job: _pekerjaanCtrl.text.trim(),
      monthlyIncome: income ?? _editBase.monthlyIncome,
    );

    // A1-10 + C08: snapshot sesi untuk menolak draft/feedback sesi lama
    // (UID switch). SessionController/AppState tetap owner sesi.
    final appState = AppState.instance;
    final revision = appState.sessionRevision;
    final sessionUid = appState.sessionUid;
    bool sessionActive() =>
        appState.sessionRevision == revision &&
        appState.sessionUid == sessionUid;

    try {
      // Tunggu konfirmasi write melalui AppState sebelum menampilkan sukses.
      await appState.updateProfile(
        newName: submitted.name,
        newEmail: _emailCtrl.text.trim(),
        newPhone: submitted.phone,
        newAddress: submitted.address,
        newCity: submitted.city,
        newJob: submitted.job,
        newIncome: submitted.monthlyIncome,
        previous: _editBase,
      );

      // A1-10: tidak memindahkan draft/feedback ke sesi lain; tidak ada
      // baseline update & tidak ada feedback bila sesi berubah / widget hilang.
      if (!mounted) return;
      if (!sessionActive()) return;

      // Success memperbarui baseline TANPA dialog dirty palsu.
      // `version` server dipertahankan; untouched field yang di-merge server
      // tetap ditangani AppState (profilePatch); baseline disamakan dengan isi
      // form yang tersimpan.
      _editBase = UserProfile.fromMap(
        submitted.toMap(),
        version: appState.profileSnapshot.version,
      );
      setState(() => _isDirty = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profil berhasil disimpan ke akun.',
            // A11: gunakan cs.onPrimary agar terbaca di kedua tema
            style: GoogleFonts.lato(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          backgroundColor: AppColors.teal,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Gagal/konflik mempertahankan input; baseline TIDAK diperbarui.
      // Tidak ada feedback sesi lama (UID switch / sesi berubah).
      if (sessionActive()) {
        setState(
          () => _saveError = e is RecordConflict || e is SyncFailure
              ? e.toString()
              : e is ArgumentError
              ? e.message.toString()
              : 'Profil belum dapat disimpan. Periksa koneksi dan coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────

  Future<void> _savePreference(Future<void> Function() save) async {
    if (AppState.instance.profileSaving) return;
    setState(() => _saveError = null);
    try {
      await save();
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = error is RecordConflict || error is SyncFailure
              ? error.toString()
              : 'Preferensi gagal disimpan. Coba lagi.',
        );
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      // A1-10: ini jalur LOGOUT PENGGUNA (user-initiated). Keputusan discard
      // draft profil yang belum disimpan harus eksplisit. Batal→tidak keluar
      // & input dipertahankan; Keluar→discard disetujui→keluar.
      //
      // BUKAN penjebak navigasi; pindah tab sendiri tidak memanggil ini.
      //
      // LOGOUT KARENA SESI SERVER INVALID TIDAK DITAHAN DRAFT: jalur itu
      // tidak melalui `_logout`; `SessionController._failed`/`_receive(null)`
      // → `AppState.clearSession()` + `SessionGate` membersihkan stack.
      // (Owner sesi tetap B/C; tidak ada perubahan shared action; lease.)
      final hasUnsavedDraft = _formState == ProfileFormState.dirty;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Keluar dari Akun?'),
          content: Text(
            'Profil yang sudah tersimpan tetap ada pada akun. Perubahan yang masih diproses belum terjamin tersimpan. Tampilan sesi dan tautan foto akan dikosongkan. Salinan yang sudah dibagikan tidak dapat ditarik kembali.'
            '${hasUnsavedDraft ? ' Perubahan profil yang belum disimpan akan dibuang.' : ''}',
          ),
          actions: [
            // Cancel discard/logout: tidak ada perubahan; draft dipertahankan.
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              key: const Key('confirm-logout'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Keluar'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final session = SessionScope.maybeOf(context);
      if (session != null) {
        // Auth gate membersihkan data dan seluruh stack, termasuk dialog aktif.
        await session.signOut();
      } else {
        await AuthService.instance.signOut();
        AppState.instance.clearSession();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (_) {
      if (mounted) _showPhotoError('Gagal keluar. Silakan coba lagi.');
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Data Diri')),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom:
              MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              32,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar ─────────────────────────────────────────────
              Center(
                child: _AvatarWidget(state: state, onTap: _pickPhoto),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Ketuk foto untuk mengubah',
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Error banner ───────────────────────────────────────
              if (_saveError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _saveError!,
                          style: GoogleFonts.lato(
                            color: cs.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Informasi Pribadi ──────────────────────────────────
              if (state.profileSaving) ...[
                const Text(
                  'Menyimpan perubahan, menunggu konfirmasi server...',
                ),
                const SizedBox(height: 12),
              ],
              _SectionLabel(label: 'Informasi Pribadi'),
              const SizedBox(height: 12),

              _AppFormField(
                key: const Key('profile-name'),
                controller: _namaCtrl,
                label: 'Nama Lengkap',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                validator: UserProfile.validateName,
              ),
              const SizedBox(height: 14),

              _AppFormField(
                key: const Key('profile-email'),
                controller: _emailCtrl,
                label: 'Email akun',
                readOnly: true,
                helperText:
                    'Email identitas tidak dapat diubah dari halaman ini.',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email wajib diisi';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                    return 'Format email tidak valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              _AppFormField(
                key: const Key('profile-phone'),
                controller: _waCtrl,
                label: 'Nomor Telepon / WhatsApp (opsional)',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hint: '+62 8xx-xxxx-xxxx atau 08xx-xxxx-xxxx',
                validator: UserProfile.validatePhone,
              ),
              const SizedBox(height: 14),

              _AppFormField(
                key: const Key('profile-address'),
                controller: _alamatCtrl,
                validator: (v) => (v?.trim().length ?? 0) > 500
                    ? 'Alamat maksimal 500 karakter'
                    : null,
                label: 'Alamat',
                icon: Icons.location_on_outlined,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),

              _AppFormField(
                key: const Key('profile-city'),
                controller: _kotaCtrl,
                validator: (v) => (v?.trim().length ?? 0) > 120
                    ? 'Kota maksimal 120 karakter'
                    : null,
                label: 'Kota / Kabupaten',
                icon: Icons.location_city_outlined,
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: 28),

              // ── Informasi Pekerjaan ────────────────────────────────
              _SectionLabel(label: 'Informasi Pekerjaan'),
              const SizedBox(height: 12),

              _AppFormField(
                key: const Key('profile-job'),
                controller: _pekerjaanCtrl,
                validator: (v) => (v?.trim().length ?? 0) > 120
                    ? 'Pekerjaan maksimal 120 karakter'
                    : null,
                label: 'Pekerjaan',
                icon: Icons.work_outline,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),

              _AppFormField(
                key: const Key('profile-income'),
                controller: _pendapatanCtrl,
                label: 'Pendapatan Bulanan (Rp)',
                icon: Icons.payments_outlined,
                keyboardType: TextInputType.number,
                // A1-13: Done karena field terakhir sebelum preferensi toggle
                textInputAction: TextInputAction.done,
                hint: 'Contoh: 5000000',
                helperText:
                    'Rupiah bulat: 5000000 atau 5.000.000. Kosong berarti 0.',
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null; // opsional
                  final val = UserProfile.parseIncome(v);
                  if (val == null) {
                    return 'Pendapatan harus berupa angka bulat non-negatif';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 28),

              // ── Preferensi ─────────────────────────────────────────
              _SectionLabel(label: 'Preferensi'),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.notifications_outlined,
                      label: 'Notifikasi Transaksi',
                      subtitle: 'Pengingat transaksi dalam aplikasi',
                      value: AppState.instance.notifEnabled,
                      onChanged: state.profileSaving
                          ? null
                          : (v) => _savePreference(() => state.setNotif(v)),
                    ),
                    Divider(color: Theme.of(context).dividerColor, height: 1),
                    _SwitchRow(
                      icon: Icons.dark_mode_outlined,
                      label: 'Mode Gelap',
                      subtitle: 'Ubah tampilan tema aplikasi',
                      value: AppState.instance.darkMode,
                      onChanged: state.profileSaving
                          ? null
                          : (v) => _savePreference(() => state.setDarkMode(v)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Simpan ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('profile-save'),
                  onPressed: _isSaving || state.profileSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Simpan Data Diri',
                          style: GoogleFonts.lato(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Akun & Keamanan (A1-18) ────────────────────────────
              // Memakai halaman B05 yang sudah ada (/account-security) dan
              // halaman lisensi bawaan Flutter (LicenseRegistry di main).
              _SectionLabel(label: 'Akun & Keamanan'),
              const SizedBox(height: 8),
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('profile-security'),
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Keamanan Akun'),
                      subtitle: const Text(
                        'Verifikasi email, metode masuk, ganti password',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed('/account-security'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('profile-licenses'),
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Lisensi Perangkat Lunak'),
                      subtitle: const Text('Font dan pustaka yang dipakai'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'SIMANJA',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Keluar ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('profile-logout'),
                  onPressed: _isLoggingOut ? null : _logout,
                  icon: const Icon(
                    Icons.logout,
                    size: 16,
                    color: AppColors.expense,
                  ),
                  label: Text(
                    'Keluar dari Akun',
                    style: GoogleFonts.lato(
                      color: AppColors.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.expense),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Profil & preferensi tersimpan di akun. '
                  'Foto profil hanya tersimpan lokal di perangkat ini.',
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              // A17: pintu masuk halaman privasi & data
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/privacy'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                  child: Text(
                    'Privasi & Data Pengguna',
                    style: GoogleFonts.lato(
                      color: AppColors.teal,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.teal,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar Widget ─────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final AppState state;
  final VoidCallback onTap;

  const _AvatarWidget({required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // A1-11: fallback tahan file hilang/korup/race (exists saja tidak cukup;
    // CircleAvatar tidak punya errorBuilder) via SafeLocalAvatar.
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          SafeLocalAvatar(
            imagePath: state.photoPath,
            radius: 52,
            backgroundColor: AppColors.teal.withValues(alpha: 0.15),
            fallbackIcon: Icons.person,
            fallbackIconColor: AppColors.teal,
            fallbackIconSize: 52,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.teal,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo Picker Sheet ────────────────────────────────────────────────────

class _PhotoPickerSheet extends StatelessWidget {
  final bool hasPhoto;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDelete;

  const _PhotoPickerSheet({
    required this.hasPhoto,
    required this.onCamera,
    required this.onGallery,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ganti Foto Profil',
              style: GoogleFonts.lato(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Foto disimpan lokal di perangkat ini.',
              style: GoogleFonts.lato(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: _IconBox(
                color: AppColors.teal,
                icon: Icons.camera_alt_outlined,
              ),
              title: Text('Kamera', style: GoogleFonts.lato(fontSize: 14)),
              onTap: onCamera,
            ),
            ListTile(
              leading: _IconBox(
                color: AppColors.chart2,
                icon: Icons.photo_library_outlined,
              ),
              title: Text('Galeri', style: GoogleFonts.lato(fontSize: 14)),
              onTap: onGallery,
            ),
            if (hasPhoto)
              ListTile(
                leading: _IconBox(
                  color: AppColors.expense,
                  icon: Icons.delete_outline,
                ),
                title: Text(
                  'Hapus Foto',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppColors.expense,
                  ),
                ),
                onTap: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _IconBox({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.teal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Form Field ────────────────────────────────────────────────────────────

class _AppFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? hint;
  final String? helperText;
  final bool readOnly;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;

  const _AppFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.hint,
    this.helperText,
    this.readOnly = false,
    this.validator,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: !AppState.instance.profileSaving,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      // A1-13: textInputAction untuk focus traversal yang logis
      textInputAction: textInputAction ?? TextInputAction.next,
      validator: validator,
      style: GoogleFonts.lato(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        helperStyle: GoogleFonts.lato(fontSize: 11),
        prefixIcon: Icon(icon),
      ),
    );
  }
}

// ── Switch Row ────────────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.lato(color: cs.onSurface, fontSize: 13),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: GoogleFonts.lato(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.teal,
            activeTrackColor: AppColors.teal.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
