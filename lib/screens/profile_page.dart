import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  final _namaCtrl = TextEditingController(text: 'Rizki Nugraha');
  final _emailCtrl = TextEditingController(text: 'rizki.nugraha@email.com');
  final _waCtrl = TextEditingController(text: '+62 812-3456-7890');
  final _alamatCtrl = TextEditingController(
    text: 'Jl. Sudirman No. 45, Jakarta Pusat',
  );
  final _kotaCtrl = TextEditingController(text: 'Jakarta');
  final _pekerjaanCtrl = TextEditingController(text: 'Software Engineer');
  final _pendapatanCtrl = TextEditingController(text: '8.500.000');

  bool _isSaving = false;

  @override
  void dispose() {
    _namaCtrl.dispose();
    _emailCtrl.dispose();
    _waCtrl.dispose();
    _alamatCtrl.dispose();
    _kotaCtrl.dispose();
    _pekerjaanCtrl.dispose();
    _pendapatanCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(seconds: 1));
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
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(title: const Text('Data Diri')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar ─────────────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.teal,
                        size: 52,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 30,
                          height: 30,
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
                            size: 14,
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
                  'Foto Profil',
                  style: GoogleFonts.lato(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Section: Informasi Pribadi ─────────────────────────────
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
                label: 'Nomor WhatsApp (WA)',
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

              // ── Section: Informasi Pekerjaan ───────────────────────────
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
                hint: 'Contoh: 8.500.000',
              ),

              const SizedBox(height: 28),

              // ── Section: Preferensi ────────────────────────────────────
              _SectionLabel(label: 'Preferensi'),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.notifications_outlined,
                      label: 'Notifikasi Transaksi',
                      value: true,
                      onChanged: (_) {},
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _SwitchRow(
                      icon: Icons.dark_mode_outlined,
                      label: 'Mode Gelap',
                      value: true,
                      onChanged: (_) {},
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _SwitchRow(
                      icon: Icons.fingerprint,
                      label: 'Autentikasi Biometrik',
                      value: false,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Save button ────────────────────────────────────────────
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

              // ── Secondary action ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {},
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
          style: GoogleFonts.lato(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
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
      style: GoogleFonts.lato(color: AppColors.textPrimary, fontSize: 14),
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
