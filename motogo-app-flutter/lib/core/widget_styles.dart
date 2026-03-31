import 'package:flutter/material.dart';
import 'theme.dart';

/// Reusable widget styles — extracted from CSS classes across all screens.
/// Provides consistent styling for cards, badges, buttons, etc.
class WidgetStyles {
  WidgetStyles._();

  /// Card decoration — mirrors .bcard from CSS.
  static BoxDecoration card({Color? color, bool elevated = true}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
    boxShadow: elevated
        ? [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)]
        : null,
  );

  /// Small card — mirrors .bcard with rsm.
  static BoxDecoration cardSmall({Color? color}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
    boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 8)],
  );

  /// Status badge decoration — mirrors .rst badge.
  static BoxDecoration statusBadge(Color bg) => BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(50),
  );

  /// Section header dark — mirrors .hdr from screens.css.
  static BoxDecoration darkHeader = const BoxDecoration(
    color: MotoGoColors.dark,
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
  );

  /// Green primary button — mirrors .btn-g.
  static ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: MotoGoColors.green,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5),
  );

  /// Outlined button — mirrors .rbtn.
  static ButtonStyle outlinedButton = OutlinedButton.styleFrom(
    foregroundColor: MotoGoColors.black,
    side: const BorderSide(color: MotoGoColors.g200, width: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  );

  /// Back button — mirrors .det-back / .bk-c green circle.
  static Widget backButton(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: MotoGoColors.green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
      ),
    ),
  );

  /// Info banner — mirrors .rd-info-banner.
  static Widget infoBanner({required String icon, required String text, Color? bg}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bg ?? MotoGoColors.greenPale,
      borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker))),
    ]),
  );

  /// Warning banner — mirrors .rd-banner-warn.
  static Widget warningBanner({required String text}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      border: Border.all(color: const Color(0xFFFDE68A)),
    ),
    child: Row(children: [
      const Text('⚠️', style: TextStyle(fontSize: 20)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)))),
    ]),
  );

  /// Price row — mirrors .pr from booking-payment.css.
  static Widget priceRow(String label, String value, {bool bold = false, Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: MotoGoColors.g600)),
        Text(value, style: TextStyle(fontSize: bold ? 16 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: valueColor ?? MotoGoColors.black)),
      ],
    ),
  );

  /// Section title — mirrors .msec-t from profile.
  static Widget sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
  );
}
