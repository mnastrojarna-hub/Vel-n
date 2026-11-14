import 'package:flutter/painting.dart';

/// v2 type scale (PLAN §1.2). Sizes / weights / line heights only — the
/// family (Montserrat) is inherited from the app theme, so v2 widgets never
/// call `GoogleFonts.*`. Numbers use [tab] (tabular figures).
abstract final class MgType {
  static const display = TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1.0);
  static const h1 = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1);
  static const h2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2);
  static const h3 = TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2);
  static const section = TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25);
  static const title = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.45);
  static const small = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4);
  static const meta = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.3);
  static const eyebrow = TextStyle(
      fontSize: 11.5, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: 0.69);
  static const micro = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.3);

  /// Calendar day price — the only allowed 10 px text.
  static const calPrice = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1.1);
  static const calDay = TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.1);
  static const cta = TextStyle(
      fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: 0.3);
  static const ctaCompact = TextStyle(
      fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: 0.3);
  static const button = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.2);
  static const code = TextStyle(
      fontSize: 24, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 4.3);
  static const codeXl = TextStyle(
      fontSize: 48, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: 8.6);
  static const nav = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 14 / 11);
  static const navActive = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, height: 14 / 11);

  static const _tabular = [FontFeature.tabularFigures()];

  /// [s] with tabular figures (prices, counts, codes, dates).
  static TextStyle tab(TextStyle s) => s.copyWith(fontFeatures: _tabular);
}
