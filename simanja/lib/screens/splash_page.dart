import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// The first Flutter-drawn screen after the native splash disappears.
///
/// Animation sequence:
///   0 ms  → native splash removed, white screen
///  300 ms → logo fades + scales in (800 ms)
///  900 ms → app name fades in (600 ms)
/// 1400 ms → loading indicator fades in (400 ms)
/// 2800 ms → navigate to /intro (pushReplacement)
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────
  late final AnimationController _controller;

  // Logo: fade + scale
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  // App name: fade + translate up
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameSlide;

  // Loading indicator: fade
  late final Animation<double> _loaderOpacity;

  // ── Timer for auto-navigation ──────────────────────────────────────────
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    // Force light status-bar icons while on the white splash
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark, // dark icons on white bg
      ),
    );

    // Single controller drives all animations over 2 000 ms
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // ── Logo ─────────────────────────────────────────────────────────────
    // Starts at 150 ms, completes at 950 ms (relative: 0.075 → 0.475)
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

    // ── App name ──────────────────────────────────────────────────────────
    // Starts at 550 ms, completes at 1 100 ms (relative: 0.275 → 0.55)
    _nameOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.275, 0.55, curve: Curves.easeIn),
    );
    _nameSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.275, 0.55, curve: Curves.easeOut),
      ),
    );

    // ── Loading indicator ─────────────────────────────────────────────────
    // Starts at 900 ms, completes at 1 300 ms (relative: 0.45 → 0.65)
    _loaderOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.65, curve: Curves.easeIn),
    );

    // Remove native splash and start animation as soon as first frame is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
      _controller.forward();
    });

    // Navigate after 2 800 ms total
    _navTimer = Timer(const Duration(milliseconds: 2800), _navigateNext);
  }

  void _navigateNext() {
    if (!mounted) return;
    // Restore dark status-bar style for the rest of the app
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    Navigator.of(context).pushReplacementNamed('/intro');
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // ── Animated Logo ──────────────────────────────────────────
              FadeTransition(
                opacity: _logoOpacity,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: _LogoWidget(),
                ),
              ),

              const SizedBox(height: 28),

              // ── App Name + Tagline ─────────────────────────────────────
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

              // ── Loading Indicator ──────────────────────────────────────
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
                          Color(0xFF52D6A4),
                        ),
                        backgroundColor:
                            const Color(0xFF52D6A4).withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Memuat data...',
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
        ),
      ),
    );
  }
}

// ── Logo Widget ────────────────────────────────────────────────────────────
/// Renders the SVG logo when available, falls back to a custom-painted
/// widget so the splash always looks correct even before the asset is placed.
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

/// Pure-Flutter fallback logo — a teal circle with a white wallet icon.
/// Shown if the SVG asset hasn't been placed yet or on web.
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      height: 130,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF52D6A4),
        boxShadow: [
          BoxShadow(
            color: Color(0x3352D6A4),
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
