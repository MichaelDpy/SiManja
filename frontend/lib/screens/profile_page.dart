import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../core/app_state.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _namaCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _waCtrl;
  late TextEditingController _alamatCtrl;
  late TextEditingController _kotaCtrl;
  late TextEditingController _pekerjaanCtrl;
  late TextEditingController _pendapatanCtrl;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final s = AppState.instance;
    _namaCtrl = TextEditingController(text: s.name);
    _emailCtrl = TextEditingController(text: s.email);
    _waCtrl = TextEditingController(text: s.phone);
    _alamatCtrl = TextEditingController(text: s.address);
    _kotaCtrl = TextEditingController(text: s.city);
    _pekerjaanCtrl = TextEditingController(text: s.job);
    _pendapatanCtrl = TextEditingController(
      text: s.monthlyIncome.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}.',
      ),
    );
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
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

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ganti Foto Profil',
                style: GoogleFonts.lato(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.teal,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Kamera',
                  style: GoogleFonts.lato(color: AppColors.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final img = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 80,
                  );
                  if (img != null) AppState.instance.updatePhoto(img.path);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.chart2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.chart2,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Galeri',
                  style: GoogleFonts.lato(color: AppColors.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final img = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 80,
                  );
                  if (img != null) AppState.instance.updatePhoto(img.path);
                },
              ),
              if (AppState.instance.photoPath != null)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.expense.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppColors.expense,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Hapus Foto',
                    style: GoogleFonts.lato(color: AppColors.expense),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    AppState.instance.updatePhoto('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final incomeText = _pendapatanCtrl.text
        .replaceAll('.', '')
        .replaceAll(',', '');
    final income =
        double.tryParse(incomeText) ?? AppState.instance.monthlyIncome;

    AppState.instance.updateProfile(
      newName: _namaCtrl.text.trim(),
      newEmail: _emailCtrl.text.trim(),
      newPhone: _waCtrl.text.trim(),
      newAddress: _alamatCtrl.text.trim(),
      newCity: _kotaCtrl.text.trim(),
      newJob: _pekerjaanCtrl.text.trim(),
      newIncome: income,
    );

    setState(() => _isSaving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Data diri berhasil disimpan!',
          style: GoogleFonts.lato(color: AppColors.bgDark),
        ),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Data Diri')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar ──────────────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: CircleAvatar(
                        radius: 52,
                        backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                        backgroundImage:
                            (state.photoPath != null &&
                                state.photoPath!.isNotEmpty)
                            ? FileImage(File(state.photoPath!))
                            : null,
                        child:
                            (state.photoPath == null ||
                                state.photoPath!.isEmpty)
                            ? const Icon(
                                Icons.person,
                                color: AppColors.teal,
                                size: 52,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.teal,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.bgDark,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: AppColors.bgDark,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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

              // ── Informasi Pribadi ────────────────────────────────────────
              _SectionLabel(label: 'Informasi Pribadi'),
              const SizedBox(height: 12),

              _FormField(
                controller: _namaCtrl,
                label: 'Nama Lengkap',
                icon: Icons.person_outline,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _emailCtrl,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email wajib diisi';
                  if (!v.contains('@')) return 'Format email tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _waCtrl,
                label: 'Nomor WhatsApp',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                hint: '+62 8xx-xxxx-xxxx',
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Nomor WA wajib diisi' : null,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _alamatCtrl,
                label: 'Alamat',
                icon: Icons.location_on_outlined,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _kotaCtrl,
                label: 'Kota / Kabupaten',
                icon: Icons.location_city_outlined,
              ),

              const SizedBox(height: 28),

              // ── Informasi Pekerjaan ──────────────────────────────────────
              _SectionLabel(label: 'Informasi Pekerjaan'),
              const SizedBox(height: 12),

              _FormField(
                controller: _pekerjaanCtrl,
                label: 'Pekerjaan',
                icon: Icons.work_outline,
              ),
              const SizedBox(height: 14),
              _FormField(
                controller: _pendapatanCtrl,
                label: 'Pendapatan Bulanan (Rp)',
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                hint: 'Contoh: 3.500.000',
              ),

              const SizedBox(height: 28),

              // ── Preferensi ───────────────────────────────────────────────
              _SectionLabel(label: 'Preferensi'),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.divider
                        : const Color(0xFFE0E4EF),
                  ),
                ),
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.notifications_outlined,
                      label: 'Notifikasi Transaksi',
                      value: state.notifEnabled,
                      onChanged: (v) => AppState.instance.setNotif(v),
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _SwitchRow(
                      icon: Icons.dark_mode_outlined,
                      label: 'Mode Gelap',
                      value: state.darkMode,
                      onChanged: (v) => AppState.instance.setDarkMode(v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Simpan ────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: AppColors.bgDark,
                    disabledBackgroundColor: AppColors.teal.withValues(
                      alpha: 0.4,
                    ),
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
                            color: AppColors.bgDark,
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

              const SizedBox(height: 12),

              // ── Keluar ────────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        title: Text(
                          'Keluar dari Akun?',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        content: Text(
                          'Semua perubahan yang belum disimpan akan hilang.',
                          style: GoogleFonts.lato(fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              'Batal',
                              style: GoogleFonts.lato(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              'Keluar',
                              style: GoogleFonts.lato(
                                color: AppColors.expense,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      AppState.instance.reset();
                      Navigator.of(context).pushReplacementNamed('/login');
                    }
                  },
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────

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
        Text(
          label,
          style: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? hint;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
    this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.lato(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.lato(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
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
