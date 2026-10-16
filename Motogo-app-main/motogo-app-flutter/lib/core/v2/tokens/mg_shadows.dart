import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'mg_colors.dart';

/// v2 shadows (v1 spec §2.5) and gradients (§2.2).
abstract final class MgShadows {
  static const card = [
    BoxShadow(offset: Offset(0, 6), blurRadius: 18, spreadRadius: -8, color: Color(0x591A2E22)),
  ];
  static const dark = [
    BoxShadow(offset: Offset(0, 18), blurRadius: 40, spreadRadius: -14, color: Color(0x990A1F14)),
  ];
  static const sticky = [
    BoxShadow(offset: Offset(0, -8), blurRadius: 24, color: Color(0x40000000)),
  ];
  static const sheet = [
    BoxShadow(offset: Offset(0, -14), blurRadius: 40, color: Color(0x590A1F14)),
  ];
  static const receipt = [
    BoxShadow(offset: Offset(0, 14), blurRadius: 30, spreadRadius: -14, color: Color(0x8C000000)),
  ];
  static const icon = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -6, color: Color(0x591A2E22)),
  ];
  static const photoControl = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -4, color: Color(0x80000000)),
  ];
}

abstract final class MgGradients {
  static const neon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [MgColors.neonHi, MgColors.neonLo],
  );
  static const dark = RadialGradient(
    center: Alignment.topRight,
    radius: 1.5,
    colors: [MgColors.glow, MgColors.panel, MgColors.night],
    stops: [0, 0.55, 1],
  );
  static const darkCta = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [MgColors.ctaDarkStop, MgColors.panel, MgColors.night],
    stops: [0, 0.6, 1],
  );
  static const progress = LinearGradient(colors: [Color(0xFF0D6E0D), MgColors.neonLo]);
  static const bar = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [MgColors.neonLo, Color(0xFF0D6E0D)],
  );
  static const barWeekend = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [MgColors.neonText, MgColors.neonLo],
  );
  static const tintFeature = LinearGradient(
    begin: Alignment(-0.34, -0.94),
    end: Alignment(0.34, 0.94),
    colors: [MgColors.tintFeatureA, MgColors.tintFeatureB],
  );
  static const offer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [MgColors.offerA, MgColors.offerB],
  );

  /// Dark hero with a rank aura as the first stop (`.rk-hero`).
  static RadialGradient hero(Color aura) => RadialGradient(
        center: Alignment.topRight,
        radius: 1.5,
        colors: [aura, MgColors.panel, MgColors.night],
        stops: const [0, 0.55, 1],
      );
}

/// CSS `linear-gradient(<deg>, …)` → Flutter [LinearGradient] (direction
/// approximated on the box; 135° = top-left → bottom-right).
LinearGradient cssLinearGradient(double deg, List<Color> colors, [List<double>? stops]) {
  final r = deg * math.pi / 180;
  var x = math.sin(r), y = -math.cos(r);
  final m = math.max(x.abs(), y.abs());
  if (m > 0) {
    x /= m;
    y /= m;
  }
  return LinearGradient(
    begin: Alignment(-x, -y),
    end: Alignment(x, y),
    colors: colors,
    stops: stops,
  );
}
