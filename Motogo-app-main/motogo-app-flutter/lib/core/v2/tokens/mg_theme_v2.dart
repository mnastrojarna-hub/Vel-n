import 'package:flutter/material.dart';

import 'mg_colors.dart';
import 'mg_space.dart';
import 'mg_type.dart';

/// Theme overlay applied on top of the app theme while the v2 look is ON
/// (main.dart integration). It changes ONLY the shapes of snackbars, dialogs,
/// bottom sheets and progress indicators, so snackbars / dialogs raised by
/// unchanged logic code get the v2 look; buttons and inputs of old screens
/// keep theirs.
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
    );
  }
}
