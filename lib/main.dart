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

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await initializeDateFormatting('id_ID', null);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SimanjaApp());
}

class SimanjaApp extends StatefulWidget {
  const SimanjaApp({super.key});

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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.darkMode;

    return MaterialApp(
      title: 'SIMANJA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      routes: {
        '/': (ctx) => const SplashPage(),
        '/intro': (ctx) => const IntroPage(),
        '/login': (ctx) => const LoginPage(),
        '/home': (ctx) => const MainShell(),
      },
    );
  }
}
