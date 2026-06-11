import 'package:flutter/material.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// Reusable widget styles — maps every CSS class to a Flutter equivalent.
// Source: elements.css, screens.css, screens-extra.css
// ═══════════════════════════════════════════════════════════════════════

class WidgetStyles {
  WidgetStyles._();

  // ── Card decorations ────────────────────────────────────────────────

  /// .bcard — main content card.
  static BoxDecoration card({Color? color, bool elevated = true}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(MotoGoRadius.card),
    boxShadow: elevated ? MotoGoShadows.card : null,
  );

  /// .bcard-sm — small / nested card.
  static BoxDecoration cardSmall({Color? color}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(MotoGoRadius.xl),
    boxShadow: MotoGoShadows.cardSmall,
  );

  /// .bcard-flat — card without shadow (border only).
  static BoxDecoration cardFlat({Color? color, Color? borderColor}) => BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(MotoGoRadius.xxl),
    border: Border.all(color: borderColor ?? MotoGoColors.g200),
  );

  // ── Header decoration ──────────────────────────────────────────────

  /// .hdr — dark section header with rounded bottom.
  static const BoxDecoration darkHeader = BoxDecoration(
    color: MotoGoColors.dark,
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
  );

  // ── Badge decorations ──────────────────────────────────────────────

  /// .rst — status badge (pill shape).
  static BoxDecoration statusBadge(Color bg) => BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
  );

  /// Status badge with border (like reservation cards).
  static BoxDecoration statusBadgeBordered(Color bg, Color borderColor) => BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
    border: Border.all(color: borderColor),
  );

  /// .tag — spec badge on moto cards (ŘP A2, Cestovní, 32 KW).
  static BoxDecoration specBadge(Color color) => BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(MotoGoRadius.sm),
    border: Border.all(color: color.withValues(alpha: 0.15)),
  );

  // ── Button styles ──────────────────────────────────────────────────

  /// .btn-g — green primary button (full width, 52px height).
  static ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: MotoGoColors.green,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(MotoGoDimens.btnPrimaryHeight),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
    textStyle: const TextStyle(
      fontWeight: MotoGoTypo.w800,
      fontSize: MotoGoTypo.sizeXl,
      letterSpacing: MotoGoTypo.lsMedium,
    ),
  );

  /// .rbtn — outlined button.
  static ButtonStyle outlinedButton = OutlinedButton.styleFrom(
    foregroundColor: MotoGoColors.black,
    side: const BorderSide(color: MotoGoColors.g200, width: MotoGoDimens.btnBorderWidth),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  );

  /// .btn-danger — red outlined button (cancel, SOS).
  static ButtonStyle dangerOutlinedButton = OutlinedButton.styleFrom(
    foregroundColor: MotoGoColors.red,
    side: const BorderSide(color: MotoGoColors.red, width: MotoGoDimens.btnBorderWidth),
    minimumSize: const Size.fromHeight(MotoGoDimens.btnPrimaryHeight),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
  );

  // ── Back button ────────────────────────────────────────────────────

  /// .det-back / .bk-c — green back circle with arrow.
  static Widget backButton(BuildContext context) => GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      width: MotoGoDimens.backBtnSize,
      height: MotoGoDimens.backBtnSize,
      decoration: BoxDecoration(
        color: MotoGoColors.green,
        borderRadius: BorderRadius.circular(MotoGoDimens.backBtnRadius),
      ),
      child: const Center(
        child: Text('←', style: TextStyle(
          fontSize: 18,
          fontWeight: MotoGoTypo.w900,
          color: Colors.black,
        )),
      ),
    ),
  );

  /// .menu-btn — green hamburger menu button.
  static Widget menuButton(VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: MotoGoDimens.menuBtnSize,
      height: MotoGoDimens.menuBtnSize,
      decoration: BoxDecoration(
        color: MotoGoColors.green,
        borderRadius: BorderRadius.circular(MotoGoDimens.menuBtnRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _menuLine(16),
          const SizedBox(height: 4),
          _menuLine(12),
          const SizedBox(height: 4),
          _menuLine(16),
        ],
      ),
    ),
  );

  static Widget _menuLine(double width) => Container(
    width: width,
    height: 2,
    decoration: BoxDecoration(
      color: MotoGoColors.dark,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  // ── Info banners ───────────────────────────────────────────────────

  /// .rd-info-banner — green info banner with icon.
  static Widget infoBanner({required String icon, required String text, Color? bg}) => Container(
    padding: const EdgeInsets.all(MotoGoSpacing.md),
    decoration: BoxDecoration(
      color: bg ?? MotoGoColors.greenPale,
      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
      border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: MotoGoSpacing.fieldGap),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: MotoGoTypo.sizeBase,
        fontWeight: MotoGoTypo.w700,
        color: MotoGoColors.greenDarker,
      ))),
    ]),
  );

  /// .rd-banner-warn — yellow warning banner.
  static Widget warningBanner({required String text}) => Container(
    padding: const EdgeInsets.all(MotoGoSpacing.md),
    decoration: BoxDecoration(
      color: MotoGoColors.amberBg,
      borderRadius: BorderRadius.circular(MotoGoRadius.xl),
      border: Border.all(color: MotoGoColors.amberBorder),
    ),
    child: Row(children: [
      const Text('⚠️', style: TextStyle(fontSize: 20)),
      const SizedBox(width: MotoGoSpacing.fieldGap),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: MotoGoTypo.sizeBase,
        fontWeight: MotoGoTypo.w700,
        color: Color(0xFF92400E),
      ))),
    ]),
  );

  // ── Price row ──────────────────────────────────────────────────────

  /// .pr — price line item (label on left, value on right).
  static Widget priceRow(String label, String value, {bool bold = false, Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: MotoGoTypo.sizeBase,
          fontWeight: bold ? MotoGoTypo.w800 : MotoGoTypo.w600,
          color: MotoGoColors.g600,
        )),
        Text(value, style: TextStyle(
          fontSize: bold ? MotoGoTypo.sizeH3 : MotoGoTypo.sizeBase,
          fontWeight: bold ? MotoGoTypo.w900 : MotoGoTypo.w600,
          color: valueColor ?? MotoGoColors.black,
        )),
      ],
    ),
  );

  // ── Section title ──────────────────────────────────────────────────

  /// .msec-t — profile / settings section title.
  static Widget sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(title, style: const TextStyle(
      fontSize: MotoGoTypo.sizeLg,
      fontWeight: MotoGoTypo.w800,
      color: MotoGoColors.g400,
      letterSpacing: MotoGoTypo.lsMedium,
    )),
  );

  // ── Input label ────────────────────────────────────────────────────

  /// .lbl — uppercase form field label above input.
  static Widget inputLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: MotoGoSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: MotoGoTypo.sizeMd,
        fontWeight: MotoGoTypo.w700,
        color: MotoGoColors.g400,
        letterSpacing: MotoGoTypo.lsMedium,
      ),
    ),
  );

  // ── Chip / filter tag ──────────────────────────────────────────────

  /// .chip — filter chip (category, license group, usage).
  static Widget chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? MotoGoColors.green : Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        border: Border.all(
          color: active ? MotoGoColors.green : MotoGoColors.g200,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: MotoGoTypo.sizeBase,
          fontWeight: MotoGoTypo.w700,
          color: active ? Colors.black : MotoGoColors.black,
        ),
      ),
    ),
  );

  // ── Dropdown container ─────────────────────────────────────────────

  /// .dd-wrap — dropdown field container with border.
  static BoxDecoration dropdownDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(MotoGoRadius.xl),
    border: Border.all(color: MotoGoColors.g200, width: 1.5),
  );

  // ── Calendar legend ────────────────────────────────────────────────

  /// Calendar legend item (colored dot + label).
  static Widget calendarLegend(Color color, String label) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
        fontSize: MotoGoTypo.sizeSm,
        color: MotoGoColors.g400,
      )),
    ],
  );

  // ── Sticky bottom bar ──────────────────────────────────────────────

  /// Container decoration for sticky CTA bars.
  static BoxDecoration stickyBar = BoxDecoration(
    color: Colors.white,
    boxShadow: MotoGoShadows.stickyBar,
  );

  // ── Pricing table cell ─────────────────────────────────────────────

  /// Per-day pricing column (dark bg with price).
  static BoxDecoration pricingCell = BoxDecoration(
    color: MotoGoColors.dark,
    borderRadius: BorderRadius.circular(MotoGoRadius.sm),
  );

  // ── Option row (pickup/return selection) ───────────────────────────

  /// Active/inactive option row decoration.
  static BoxDecoration optionRow({required bool active}) => BoxDecoration(
    color: active ? MotoGoColors.greenPale : MotoGoColors.g100,
    borderRadius: BorderRadius.circular(MotoGoRadius.xl),
    border: Border.all(
      color: active ? MotoGoColors.green : MotoGoColors.g200,
      width: active ? 2 : 1,
    ),
  );

  // ── Date box (VYZVEDNUTÍ / VRÁCENÍ) ────────────────────────────────

  /// Green-bordered date display box.
  static BoxDecoration dateBox({bool active = true}) => BoxDecoration(
    color: active ? MotoGoColors.greenPale : Colors.white,
    borderRadius: BorderRadius.circular(MotoGoRadius.xl),
    border: Border.all(
      color: active ? MotoGoColors.green : MotoGoColors.g200,
      width: 1.5,
    ),
  );
}
