import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet warna SIMANJA.
///
/// Widget sebaiknya mengambil warna dari [Theme.of(context).colorScheme]
/// bukan langsung dari [AppColors], kecuali warna chart, status, dan teal
/// yang memang konstan di kedua tema.
class AppColors {
  AppColors._();

  // ── Background (dark-only; light memakai colorScheme.surface) ───────────
  static const Color bgDark = Color(0xFF1A1F2E);
  static const Color bgCard = Color(0xFF242A3B);
  static const Color bgCardAlt = Color(0xFF1E2536);

  // ── Accent teal — identitas SIMANJA, konstan di kedua tema ───────────────
  static const Color teal = Color(0xFF2DD4BF);
  static const Color tealDark = Color(0xFF0F9E8A);
  static const Color tealLight = Color(0xFF5EEAD4);

  // ── Text (dark-only; light memakai colorScheme.onSurface / onSurfaceVariant)
  static const Color textPrimary = Color(0xFFE8EAF0);
  static const Color textSecondary = Color(0xFF8B92A9);
  static const Color textMuted = Color(0xFF555E7A);

  // ── Text light — dipakai widget saat mode terang tanpa akses context ─────
  static const Color textPrimaryLight = Color(0xFF1A1F2E);
  static const Color textSecondaryLight = Color(0xFF555E7A);
  static const Color textMutedLight = Color(0xFF8B92A9);

  // ── Chart — konstan, dipakai fl_chart dan legenda ────────────────────────
  static const Color chart1 = Color(0xFF2DD4BF);
  static const Color chart2 = Color(0xFF818CF8);
  static const Color chart3 = Color(0xFFFB923C);
  static const Color chart4 = Color(0xFFF472B6);
  static const Color chart5 = Color(0xFF34D399);
  static const Color chart6 = Color(0xFFFBBF24);

  // ── Status — semantik income/expense/neutral ──────────────────────────────
  static const Color income = Color(0xFF34D399);
  static const Color expense = Color(0xFFF87171);
  static const Color neutral = Color(0xFF8B92A9);

  // ── Divider ───────────────────────────────────────────────────────────────
  static const Color divider = Color(0xFF2E3650);
  static const Color dividerLight = Color(0xFFE0E4EF);
}

class AppTheme {
  AppTheme._();

  // ── Shared error color ────────────────────────────────────────────────────
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _errorColorLight = Color(0xFFD32F2F);

  static ThemeData get dark {
    const cs = ColorScheme.dark(
      primary: AppColors.teal,
      onPrimary: AppColors.bgDark,
      primaryContainer: Color(0xFF0F4A44),
      onPrimaryContainer: AppColors.tealLight,
      secondary: AppColors.tealLight,
      onSecondary: AppColors.bgDark,
      secondaryContainer: Color(0xFF1A3D3A),
      onSecondaryContainer: AppColors.tealLight,
      tertiary: AppColors.chart2,
      onTertiary: AppColors.bgDark,
      surface: AppColors.bgCard,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.divider,
      outlineVariant: Color(0xFF3A4260),
      error: _errorColor,
      onError: AppColors.bgDark,
      errorContainer: Color(0xFF4A1515),
      onErrorContainer: Color(0xFFFFB4AB),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.bgDark,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: cs,
      textTheme: _buildTextTheme(
        primary: AppColors.textPrimary,
        secondary: AppColors.textSecondary,
        muted: AppColors.textMuted,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.lato(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerColor: AppColors.divider,
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: _buildInputTheme(
        fill: AppColors.bgCard,
        border: AppColors.divider,
        focused: AppColors.teal,
        error: _errorColor,
        label: AppColors.textSecondary,
        hint: AppColors.textMuted,
        icon: AppColors.textSecondary,
        disabled: const Color(0xFF2A3048),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buildElevatedButtonStyle(
          bg: AppColors.teal,
          fg: AppColors.bgDark,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal,
          textStyle: GoogleFonts.lato(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.teal,
          side: const BorderSide(color: AppColors.teal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.lato(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.teal,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.bgCardAlt,
        selectedColor: AppColors.teal.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.lato(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  static ThemeData get light {
    const bgScaffold = Color(0xFFF5F6FA);
    const bgSurface = Colors.white;
    const textMain = Color(0xFF1A1F2E);
    const textSub = Color(0xFF555E7A);
    const textFaint = Color(0xFF8B92A9);
    const borderCol = Color(0xFFE0E4EF);
    const disabledFill = Color(0xFFF0F2F8);

    const cs = ColorScheme.light(
      primary: AppColors.teal,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFB2F5EE),
      onPrimaryContainer: Color(0xFF003733),
      secondary: AppColors.tealDark,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFB2EDE8),
      onSecondaryContainer: Color(0xFF003733),
      tertiary: AppColors.chart2,
      onTertiary: Colors.white,
      surface: bgSurface,
      onSurface: textMain,
      onSurfaceVariant: textSub,
      outline: borderCol,
      outlineVariant: Color(0xFFCED3E0),
      error: _errorColorLight,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: textMain,
      onInverseSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgScaffold,
      colorScheme: cs,
      textTheme: _buildTextTheme(
        primary: textMain,
        secondary: textSub,
        muted: textFaint,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.lato(
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textMain),
        actionsIconTheme: const IconThemeData(color: textSub),
      ),
      cardTheme: const CardThemeData(
        color: bgSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerColor: borderCol,
      dividerTheme: const DividerThemeData(
        color: borderCol,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: _buildInputTheme(
        fill: bgSurface,
        border: borderCol,
        focused: AppColors.teal,
        error: _errorColorLight,
        label: textSub,
        hint: textFaint,
        icon: textFaint,
        disabled: disabledFill,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _buildElevatedButtonStyle(bg: AppColors.teal, fg: Colors.white),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.teal,
          textStyle: GoogleFonts.lato(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.teal,
          side: const BorderSide(color: AppColors.teal),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.lato(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgSurface,
        selectedItemColor: AppColors.teal,
        unselectedItemColor: textFaint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      iconTheme: const IconThemeData(color: textSub),
      chipTheme: ChipThemeData(
        backgroundColor: bgScaffold,
        selectedColor: AppColors.teal.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.lato(color: textSub, fontSize: 12),
        side: const BorderSide(color: borderCol),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static TextTheme _buildTextTheme({
    required Color primary,
    required Color secondary,
    required Color muted,
  }) {
    return GoogleFonts.latoTextTheme(
      TextTheme(
        displayLarge: TextStyle(color: primary),
        displayMedium: TextStyle(color: primary),
        displaySmall: TextStyle(color: primary),
        headlineLarge: TextStyle(color: primary),
        headlineMedium: TextStyle(color: primary),
        headlineSmall: TextStyle(color: primary),
        titleLarge: TextStyle(color: primary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: primary, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: secondary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: primary),
        bodyMedium: TextStyle(color: secondary),
        bodySmall: TextStyle(color: muted),
        labelLarge: TextStyle(color: primary, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(color: secondary),
        labelSmall: TextStyle(color: muted),
      ),
    );
  }

  static InputDecorationTheme _buildInputTheme({
    required Color fill,
    required Color border,
    required Color focused,
    required Color error,
    required Color label,
    required Color hint,
    required Color icon,
    required Color disabled,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: focused, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border.withValues(alpha: 0.4)),
      ),
      labelStyle: TextStyle(color: label),
      hintStyle: TextStyle(color: hint),
      errorStyle: TextStyle(color: error, fontSize: 12),
      prefixIconColor: icon,
      suffixIconColor: icon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  static ButtonStyle _buildElevatedButtonStyle({
    required Color bg,
    required Color fg,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withValues(alpha: 0.38),
      disabledForegroundColor: fg.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      minimumSize: const Size(44, 48),
      textStyle: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w700),
      elevation: 0,
    );
  }
}
