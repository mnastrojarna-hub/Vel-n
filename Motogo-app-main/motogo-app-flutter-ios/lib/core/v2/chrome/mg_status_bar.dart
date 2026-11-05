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
/// Old look: untouched — the old screens that lie under the status bar in
/// the v2 look (root routes, old screens inside the shell) use it through
/// the `mgV1StatusBar` seam only.
class MgStatusBar extends StatelessWidget {
  /// The surface under the status bar is dark → light (white) icons.
  final bool dark;
  final Widget child;

  /// Height of an invisible strip ABOVE [child] that declares the same
  /// style (0 = none). For a top surface INSIDE a scroll view: an iOS bounce
  /// / pull-to-refresh paints the first sliver below the top edge, the page
  /// base would win under the status bar for the length of the bounce and
  /// the icons would blink; the strip keeps the surface's style while it is
  /// pushed down. Not painted, not hit-tested, outside the child's bounds
  /// (no layout change) — only ever use it on a surface at the TOP of a
  /// page, never on one that can sit mid-page.
  final double extendAbove;

  /// [extendAbove] of the heroes / app bar at the top of a scroll view —
  /// more than any bounce.
  static const double bounce = 400;

  const MgStatusBar({super.key, required this.dark, this.extendAbove = 0, required this.child});

  /// For a surface of [color] (dark / light by its luminance).
  MgStatusBar.forColor(Color color, {super.key, this.extendAbove = 0, required this.child}) : dark = isDark(color);

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
  Widget build(BuildContext context) {
    final style = styleFor(dark: dark);
    final region = AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: child);
    if (extendAbove <= 0) return region;
    // passthrough: the child gets the same constraints and sets the size —
    // the Stack adds nothing to the layout.
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        region,
        Positioned(
          left: 0,
          right: 0,
          top: -extendAbove,
          height: extendAbove,
          child: IgnorePointer(
            child: AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: const SizedBox.expand()),
          ),
        ),
      ],
    );
  }
}
