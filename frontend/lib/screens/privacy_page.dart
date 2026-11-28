import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Halaman informasi privasi dan data pengguna SIMANJA.
///
/// A17: Sediakan inventory data, kontrol, dan tautan dukungan.
/// Konten ini mencerminkan implementasi aktual tahap ini — bukan policy generik.
/// Owner hosting (B14) perlu mempublikasikan versi hosted sebelum publish store.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Privasi & Data')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Data yang Dikumpulkan', tt),
            const SizedBox(height: 8),
            _InfoCard(
              cs: cs,
              items: const [
                _DataItem(
                  icon: Icons.person_outline,
                  title: 'Profil Akun',
                  detail:
                      'Nama, nomor telepon, alamat, kota, pekerjaan, pendapatan '
                      'bulanan, dan preferensi tema/notifikasi. Disimpan di '
                      'Firebase Firestore milik akun kamu.',
                ),
                _DataItem(
                  icon: Icons.swap_horiz,
                  title: 'Transaksi Keuangan',
                  detail:
                      'Kategori, keterangan, jumlah, jenis (pemasukan/pengeluaran), '
                      'dan tanggal. Disimpan di Firebase Firestore, hanya dapat '
                      'diakses oleh akun kamu sendiri.',
                ),
                _DataItem(
                  icon: Icons.photo_outlined,
                  title: 'Foto Profil',
                  detail:
                      'Disimpan LOKAL di perangkat ini saja. Tidak diunggah ke '
                      'server atau Firebase Storage. Tampilan foto dikosongkan '
                      'saat keluar atau berganti akun.',
                ),
                _DataItem(
                  icon: Icons.email_outlined,
                  title: 'Email & Autentikasi',
                  detail:
                      'Email, status verifikasi email, dan metode masuk '
                      '(email/password atau Google) dikelola oleh Firebase '
                      'Auth. Password tidak disimpan oleh aplikasi. Sesi '
                      'masuk diingat di perangkat sampai kamu keluar.',
                ),
                _DataItem(
                  icon: Icons.storage_outlined,
                  title: 'Data di Perangkat',
                  detail:
                      'Penyimpanan cache Firestore di disk dinonaktifkan untuk '
                      'sesi baru, dan data akun dibersihkan dari tampilan saat '
                      'keluar. Ini bukan penghapusan aman: berkas sementara '
                      'atau cache lama di perangkat tidak dijamin hilang.',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle('Kontrol Data Kamu', tt),
            const SizedBox(height: 8),
            _InfoCard(
              cs: cs,
              items: const [
                _DataItem(
                  icon: Icons.edit_outlined,
                  title: 'Edit Profil',
                  detail: 'Ubah data profil kapan saja dari halaman Data Diri.',
                ),
                _DataItem(
                  icon: Icons.download_outlined,
                  title: 'Ekspor Transaksi',
                  detail:
                      'Bagikan transaksi sesuai filter aktif sebagai file CSV '
                      'dari halaman Data. File yang sudah kamu bagikan ke '
                      'aplikasi lain tidak dapat ditarik kembali oleh SIMANJA.',
                ),
                _DataItem(
                  icon: Icons.shield_outlined,
                  title: 'Keamanan Akun',
                  detail:
                      'Cek status verifikasi email, kelola metode masuk, dan '
                      'ganti password dari Profil → Keamanan Akun.',
                ),
                _DataItem(
                  icon: Icons.delete_outline,
                  title: 'Hapus Akun',
                  detail:
                      'Hapus akun beserta datanya belum dapat dilakukan dari '
                      'aplikasi. Fitur ini sedang disiapkan dan akan muncul '
                      'di sini setelah tersedia.',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle('SDK & Layanan Pihak Ketiga', tt),
            const SizedBox(height: 8),
            _InfoCard(
              cs: cs,
              items: const [
                _DataItem(
                  icon: Icons.cloud_outlined,
                  title: 'Firebase (Google)',
                  detail:
                      'Autentikasi, penyimpanan data, dan layanan akun memakai '
                      'Firebase Auth, Cloud Firestore, dan Cloud Functions. '
                      'Kebijakan privasi Google berlaku untuk layanan ini.',
                ),
                _DataItem(
                  icon: Icons.login,
                  title: 'Google Sign-In',
                  detail:
                      'Opsional. Bila kamu masuk atau menghubungkan akun '
                      'dengan Google, Google memberi aplikasi identitas akun '
                      '(email dan ID akun) untuk Firebase Auth.',
                ),
                _DataItem(
                  icon: Icons.font_download_outlined,
                  title: 'Font Lato',
                  detail:
                      'Font Lato dibundel di dalam aplikasi dan tidak diunduh '
                      'dari internet. Lisensi SIL Open Font License dapat '
                      'dilihat di Profil → Lisensi Perangkat Lunak.',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle('Dukungan', tt),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tidak ada alamat dukungan yang nyata dari pemilik;
                  // jangan menampilkan kontak dummy (A1-18).
                  Text(
                    'Kontak dukungan resmi belum tersedia.',
                    key: const Key('privacy-contact-pending'),
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  // A17: URL dukungan — owner B14 perlu mempublikasikan
                  // sebelum klaim ini dapat diverifikasi publik.
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Policy URL belum dipublikasikan. '
                          'Tersedia setelah hosting aktif (B14).',
                          style: GoogleFonts.lato(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Versi informasi ini mencerminkan fitur aktual aplikasi '
              'saat ini dan akan diperbarui seiring perkembangan fitur.',
              style: GoogleFonts.lato(color: AppColors.textMuted, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final TextTheme tt;
  const _SectionTitle(this.text, this.tt);

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
        Text(text, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ColorScheme cs;
  final List<_DataItem> items;
  const _InfoCard({required this.cs, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final item = e.value;
          final isLast = e.key == items.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, size: 18, color: AppColors.teal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: GoogleFonts.lato(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.detail,
                            style: GoogleFonts.lato(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor,
                  indent: 46,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _DataItem {
  final IconData icon;
  final String title;
  final String detail;
  const _DataItem({
    required this.icon,
    required this.title,
    required this.detail,
  });
}
