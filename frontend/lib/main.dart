import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme.dart';
import 'core/app_state.dart';
import 'screens/bootstrap_page.dart';
import 'screens/auth_form_page.dart';
import 'services/auth_service.dart';
import 'screens/intro_page.dart';
import 'screens/login_page.dart';
import 'screens/session_gate.dart';

/// Bootstrap Firebase -> splash -> pemeriksaan sesi.
/// Sesi aktif menuju Home; pengguna tanpa sesi melewati Intro dan Login.
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
  final AuthGateway? auth;

  const SimanjaApp({super.key, this.initialRoute = '/', this.auth});

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

  Route<void> _route(RouteSettings settings) {
    final page = switch (settings.name) {
      '/intro' => const IntroPage(),
      '/login' => LoginPage(auth: widget.auth),
      '/home' => SessionGate(auth: widget.auth),
      '/session' => SessionGate(
        auth: widget.auth,
        showIntroWhenSignedOut: true,
      ),
      '/register' => AuthFormPage(register: true, auth: widget.auth),
      '/reset-password' => AuthFormPage(register: false, auth: widget.auth),
      _ => const BootstrapPage(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
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
      onGenerateInitialRoutes: (route) => [_route(RouteSettings(name: route))],
      onGenerateRoute: _route,
      builder: (context, child) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDarkMode
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDarkMode
                ? Brightness.dark
                : Brightness.light,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
