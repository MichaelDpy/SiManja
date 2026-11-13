import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'core/app_state.dart';
import 'screens/splash_page.dart';
import 'screens/intro_page.dart';
import 'screens/login_page.dart';
import 'screens/main_shell.dart';

/// Entry point aplikasi SIMANJA.
///
/// Alur saat ini (tahap frontend lokal):
///   Splash → Intro → Login → Home
///
/// Handoff untuk Anggota 3 (C1/C3):
/// - C1: tambahkan inisialisasi Firebase di sini (Firebase.initializeApp)
///       sebelum runApp, setelah FlutterNativeSplash.preserve.
/// - C3: tambahkan auth gate di sini atau di SplashPage._navigateNext —
///       jika user sudah login, lewati Intro+Login langsung ke Home.
///       Gunakan rute '/home' yang sudah terdaftar; jangan ganti nama rute.
/// - Jangan ubah initialRoute '/' atau nama rute lain tanpa koordinasi A.
void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await initializeDateFormatting('id_ID', null);

  // Status bar awal: ikon gelap untuk splash yang berlatar putih.
  // SimanjaApp akan menyesuaikan ulang sesuai tema aktif.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SimanjaApp());
}

class SimanjaApp extends StatefulWidget {
  final String initialRoute;

  const SimanjaApp({super.key, this.initialRoute = '/'});

  @override
  State<SimanjaApp> createState() => _SimanjaAppState();
}

class _SimanjaAppState extends State<SimanjaApp> {
  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    _applyStatusBarStyle(AppState.instance.darkMode);
    if (mounted) setState(() {});
  }

  /// Perbarui status bar sesuai brightness tema aktif.
  ///
  /// Mode gelap → ikon status bar terang (terlihat di latar gelap).
  /// Mode terang → ikon status bar gelap (terlihat di latar putih).
  void _applyStatusBarStyle(bool isDark) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.darkMode;
    _applyStatusBarStyle(isDark);

    return MaterialApp(
      title: 'SIMANJA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: widget.initialRoute,
      routes: {
        '/': (ctx) => const SplashPage(),
        '/intro': (ctx) => const IntroPage(),
        '/login': (ctx) => const LoginPage(),
        '/home': (ctx) => const MainShell(),
      },
      builder: (context, child) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDarkMode ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                isDarkMode ? Brightness.dark : Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
