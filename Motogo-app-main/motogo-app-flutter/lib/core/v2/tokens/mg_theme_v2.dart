import 'package:flutter/material.dart';

import 'mg_colors.dart';
import 'mg_space.dart';
import 'mg_type.dart';

/// Theme overlay applied on top of the app theme while the v2 look is ON
/// (main.dart integration). It changes ONLY the shapes of snackbars, dialogs,
/// bottom sheets and progress indicators, so snackbars / dialogs raised by
/// unchanged logic code get the v2 look; buttons of old screens keep theirs.
/// Old text fields / selects inside v2 flows get the §2.1 `lineInput` look
/// (white fill, 1.5 px `#7C958A`, focus 2 px `#0D6E0D`, error `#B42318`, r12)
/// and an ink cursor instead of the neon one (R5 contrast).
abstract final class MgThemeV2 {
  static ThemeData overlay(ThemeData base) {
    return base.copyWith(
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MgColors.night.withValues(alpha: 0.96),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: MgColors.neonA(0.25)),
        ),
        contentTextStyle: MgType.small.copyWith(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: MgColors.onDark,
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
        ),
        actionTextColor: MgColors.neon,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MgColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MgRadius.sheet)),
        titleTextStyle: MgType.h3.copyWith(
          color: MgColors.ink,
          fontFamily: base.textTheme.titleLarge?.fontFamily,
        ),
        contentTextStyle: MgType.body.copyWith(
          color: MgColors.body2,
          fontFamily: base.textTheme.bodyMedium?.fontFamily,
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(MgRadius.sheet)),
        ),
        showDragHandle: false,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(color: MgColors.neon),
      inputDecorationTheme: _inputs(base),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: MgColors.ink,
        selectionColor: MgColors.neonA(0.35),
        selectionHandleColor: MgColors.link,
      ),
    );
  }

  /// No enabled / focused border on purpose: a field that sets
  /// `border: InputBorder.none` (search pills, collapsed fields) stays
  /// borderless, every other one gets its side from [activeIndicatorBorder]
  /// by state (Material 3 filled path) on its own or the r12 shape.
  static InputDecorationTheme _inputs(ThemeData base) {
    final b = base.inputDecorationTheme;
    return InputDecorationTheme(
      filled: true,
      fillColor: MgColors.surface,
      contentPadding: b.contentPadding,
      labelStyle: (b.labelStyle ?? const TextStyle()).copyWith(color: MgColors.meta),
      hintStyle: const TextStyle(color: MgColors.meta),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MgColors.lineInput, width: 1.5),
      ),
      activeIndicatorBorder: WidgetStateBorderSide.resolveWith((s) {
        final focused = s.contains(WidgetState.focused);
        if (s.contains(WidgetState.disabled)) return const BorderSide(color: MgColors.line, width: 1.5);
        if (s.contains(WidgetState.error)) return BorderSide(color: MgColors.err, width: focused ? 2 : 1.5);
        if (focused) return const BorderSide(color: MgColors.focusLight, width: 2);
        return const BorderSide(color: MgColors.lineInput, width: 1.5);
      }),
    );
  }
}
