import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/theme.dart';
import 'screens/splash_page.dart';
import 'screens/intro_page.dart';
import 'screens/main_shell.dart';

void main() {
  // Preserve the native splash until SplashPage explicitly removes it
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // dark icons on white splash
    ),
  );

  runApp(const SimanjaApp());
}

class SimanjaApp extends StatelessWidget {
  const SimanjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIMANJA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // App starts at the Flutter splash screen
      initialRoute: '/',
      routes: {
        '/': (ctx) => const SplashPage(), // ← animated splash
        '/intro': (ctx) => const IntroPage(), // ← onboarding / landing
        '/home': (ctx) => const MainShell(), // ← main dashboard shell
      },
    );
  }
}
