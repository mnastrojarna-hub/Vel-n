import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MotoGo24 colors — extracted from main.css :root variables.
class MotoGoColors {
  MotoGoColors._();

  static const Color bg = Color(0xFFDFF0EC);
  static const Color bg2 = Color(0xFFCDE8E2);
  static const Color black = Color(0xFF0F1A14);
  static const Color dark = Color(0xFF1A2E22);
  static const Color green = Color(0xFF74FB71);
  static const Color greenDark = Color(0xFF3DBA3A);
  static const Color greenDarker = Color(0xFF1A8A18);
  static const Color greenPale = Color(0xFFE8FFE8);
  static const Color g100 = Color(0xFFF1FAF7);
  static const Color g200 = Color(0xFFD4E8E0);
  static const Color g400 = Color(0xFF8AAB99);
  static const Color g600 = Color(0xFF4A6357);
  static const Color red = Color(0xFFEF4444);
  static const Color white = Colors.white;
}

/// MotoGo24 theme — dark motorcycle theme matching the original app.
class MotoGoTheme {
  MotoGoTheme._();

  static const double radiusLg = 18.0;
  static const double radiusSm = 12.0;

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.montserratTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: MotoGoColors.bg,
      colorScheme: ColorScheme.dark(
        primary: MotoGoColors.green,
        onPrimary: MotoGoColors.black,
        secondary: MotoGoColors.greenDark,
        surface: MotoGoColors.bg,
        onSurface: MotoGoColors.black,
        error: MotoGoColors.red,
      ),
      textTheme: textTheme.apply(
        bodyColor: MotoGoColors.black,
        displayColor: MotoGoColors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MotoGoColors.dark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: MotoGoColors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MotoGoColors.black,
          side: const BorderSide(color: MotoGoColors.g200, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MotoGoColors.g100,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: MotoGoColors.g200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: MotoGoColors.g200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: MotoGoColors.green, width: 2),
        ),
        labelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: MotoGoColors.g400,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: MotoGoColors.greenDark,
        unselectedItemColor: MotoGoColors.g400,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MotoGoColors.dark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
