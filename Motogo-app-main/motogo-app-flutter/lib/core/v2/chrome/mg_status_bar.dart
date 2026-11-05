import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Status-bar icon brightness of the v2 look (fix:statusbar). `main.dart`
/// sets ONE global style — white clock / battery, chosen for the old dark
/// tops — and v2 has light tops (canvas, white app bar, the collapsed pinned
/// bar) where white icons vanish. Every v2 surface that can lie under the
/// status bar wraps itself in [MgStatusBar]: an
/// `AnnotatedRegion<SystemUiOverlayStyle>`. Flutter applies the TOPMOST
/// region under the status-bar centre of each frame, so a dark hero inside a
/// light page, the collapsed bar painted over it, or a page pushed over the
/// shell each win while they are the surface there — nothing is computed
/// twice and a scrolled-away hero stops counting by itself.
///
/// Only the status-bar fields are set — [Brightness] for BOTH platforms
/// (`statusBarIconBrightness` = Android, `statusBarBrightness` = iOS, which
/// names the BACKGROUND), a transparent bar and no contrast scrim, like
/// `main.dart`. The navigation-bar fields stay null, so the nav bar keeps the
/// style `main.dart` gave it (Flutter forwards null fields as "unchanged").
/// Old look: untouched — nothing outside v2 uses this.
class MgStatusBar extends StatelessWidget {
  /// The surface under the status bar is dark → light (white) icons.
  final bool dark;
  final Widget child;

  const MgStatusBar({super.key, required this.dark, required this.child});

  /// For a surface of [color] (dark / light by its luminance).
  MgStatusBar.forColor(Color color, {super.key, required this.child}) : dark = isDark(color);

  /// Light icons over a dark surface.
  static const SystemUiOverlayStyle onDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  /// Dark icons over a light surface.
  static const SystemUiOverlayStyle onLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );

  static SystemUiOverlayStyle styleFor({required bool dark}) => dark ? onDark : onLight;

  /// Whether [color] is a dark surface (alpha ignored: a `.94` canvas bar
  /// over content is still light).
  static bool isDark(Color color) => ThemeData.estimateBrightnessForColor(color) == Brightness.dark;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: styleFor(dark: dark),
        child: child,
      );
}
