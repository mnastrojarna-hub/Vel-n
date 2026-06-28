import 'package:flutter/material.dart';

/// Barvy MotoGo24 — sjednocené s hlavní appkou (core/theme.dart).
class MG {
  MG._();

  static const Color green = Color(0xFF74FB71);
  static const Color greenDark = Color(0xFF3DBA3A);
  static const Color greenDarker = Color(0xFF1A8A18);
  static const Color black = Color(0xFF0F1A14);
  static const Color dark = Color(0xFF1A2E22);
  static const Color white = Colors.white;

  static const Color red = Color(0xFFEF4444);
  static const Color amber = Color(0xFFD97706);

  // Tmavý gradient pozadí kiosku
  static const Color gradientTop = Color(0xFF0A1A10);
  static const Color gradientMid = Color(0xFF152A1C);
  static const Color gradientBot = Color(0xFF1A3524);

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientTop, gradientMid, gradientBot],
  );

  /// Sklenený panel (glass) na tmavém pozadí.
  static BoxDecoration glass({double radius = 24}) => BoxDecoration(
        color: white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: white.withValues(alpha: 0.12), width: 1),
      );
}
