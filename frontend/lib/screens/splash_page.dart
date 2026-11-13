import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Layar pertama yang ditampilkan setelah native splash selesai.
///
/// Urutan animasi:
///    0 ms → native splash dihapus, layar putih
///  150 ms → logo muncul dengan fade + scale (800 ms)
///  550 ms → nama aplikasi muncul dengan fade + slide (550 ms)
///  900 ms → indikator loading muncul dengan fade (400 ms)
/// 2800 ms → navigasi ke /intro
///
/// Handoff untuk Anggota 3 (C3):
/// - Ganti _navigateNext() untuk memeriksa status sesi Firebase Auth.
///   Jika sudah login → pushReplacementNamed('/home').
///   Jika belum login → pushReplacementNamed('/intro') (alur sekarang).
/// - Jangan ubah durasi timer atau nama rute tanpa koordinasi A.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _loaderOpacity;

  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    // Splash berlatar putih — paksa ikon status bar gelap selama splash.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Logo: 150–950 ms
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.075, 0.475, curve: Curves.easeIn),
    );
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.075, 0.475, curve: Curves.elasticOut),
      ),
    );

    // Nama aplikasi: 550–1100 ms
    _nameOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.275, 0.55, curve: Curves.easeIn),
    );
    _nameSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.275, 0.55, curve: Curves.easeOut),
          ),
        );

    // Indikator loading: 900–1300 ms
    _loaderOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.65, curve: Curves.easeIn),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FlutterNativeSplash.remove();
      } catch (_) {
        // Lingkungan testing atau platform tanpa channel native
      }
      _controller.forward();
    });

    _navTimer = Timer(const Duration(milliseconds: 2800), _navigateNext);
  }

  /// Navigasi setelah splash selesai.
  ///
  /// Alur sekarang: → /intro
  /// C3: periksa sesi Firebase Auth di sini sebelum navigasi.
  void _navigateNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/intro');
  }

  @override
  void dispose() {
    // Batalkan timer dan controller agar navigasi dan animasi tidak terjadi dari widget yang sudah dilepas.
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 460;
              if (isCompact) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeTransition(
                          opacity: _logoOpacity,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: const _LogoWidget(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeTransition(
                          opacity: _nameOpacity,
                          child: SlideTransition(
                            position: _nameSlide,
                            child: Column(
                              children: [
                                Text(
                                  'SIMANJA',
                                  style: GoogleFonts.lato(
                                    color: const Color(0xFF1A1F2E),
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sistem Manajemen Keuangan',
                                  style: GoogleFonts.lato(
                                    color: const Color(0xFF8B92A9),
                                    fontSize: 12,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FadeTransition(
                          opacity: _loaderOpacity,
                          child: Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF2DD4BF),
                                  ),
                                  backgroundColor: const Color(0xFF2DD4BF)
                                      .withValues(alpha: 0.15),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Memuat...',
                                style: GoogleFonts.lato(
                                  color: const Color(0xFF8B92A9),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),
                    FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const _LogoWidget(),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _nameOpacity,
                      child: SlideTransition(
                        position: _nameSlide,
                        child: Column(
                          children: [
                            Text(
                              'SIMANJA',
                              style: GoogleFonts.lato(
                                color: const Color(0xFF1A1F2E),
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sistem Manajemen Keuangan',
                              style: GoogleFonts.lato(
                                color: const Color(0xFF8B92A9),
                                fontSize: 13,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    FadeTransition(
                      opacity: _loaderOpacity,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF2DD4BF),
                              ),
                              backgroundColor: const Color(0xFF2DD4BF)
                                  .withValues(alpha: 0.15),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Memuat...',
                            style: GoogleFonts.lato(
                              color: const Color(0xFF8B92A9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Logo widget ───────────────────────────────────────────────────────────

class _LogoWidget extends StatelessWidget {
  const _LogoWidget();

  static const _svgPath = 'assets/images/logo_simanja.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _svgPath,
      width: 130,
      height: 130,
      placeholderBuilder: (_) => const _FallbackLogo(),
    );
  }
}

/// Fallback logo — lingkaran teal dengan ikon dompet putih.
/// Ditampilkan jika aset SVG belum tersedia.
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2DD4BF),
        boxShadow: [
          BoxShadow(
            color: Color(0x332DD4BF),
            blurRadius: 32,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.account_balance_wallet_rounded,
        color: Colors.white,
        size: 64,
      ),
    );
  }
}
