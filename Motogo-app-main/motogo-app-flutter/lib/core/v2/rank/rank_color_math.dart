// Colour math of appdesign/research/rankTheme.js (sRGB, WCAG 2.x) — same
// rounding and step sizes as the JS source, so the solver reproduces the
// generated ramp table bit for bit (± rounding).
import 'dart:math' as math;

const kRankWhite = '#FFFFFF', kRankBlack = '#000000';

List<int> _rgb(String h) =>
    [1, 3, 5].map((i) => int.parse(h.substring(i, i + 2), radix: 16)).toList();

String _hex(List<double> c) =>
    '#${c.map((v) => v.round().clamp(0, 255).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

double _lin(int v) {
  final x = v / 255;
  return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
}

/// sRGB channels 0–255 of a `#RRGGBB` colour.
List<int> rankRgb(String h) => _rgb(h);

/// WCAG relative luminance of a `#RRGGBB` colour.
double rankLum(String h) {
  final c = _rgb(h).map(_lin).toList();
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

/// WCAG contrast ratio of two `#RRGGBB` colours.
double rankContrast(String a, String b) {
  final x = rankLum(a), y = rankLum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Linear sRGB mix (same rounding as the JS source).
String rankMix(String a, String b, double t) {
  final aa = _rgb(a), bb = _rgb(b);
  return _hex(List.generate(3, (i) => aa[i] + (bb[i] - aa[i]) * t));
}

/// HSL of a `#RRGGBB` colour: [hue 0–360, saturation 0–1, lightness 0–1].
List<double> rankHsl(String h) {
  final c = _rgb(h).map((v) => v / 255).toList();
  final r = c[0], g = c[1], b = c[2];
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final l = (mx + mn) / 2, d = mx - mn;
  if (d == 0) return [0, 0, l];
  final s = d / (1 - (2 * l - 1).abs());
  final hh = mx == r ? ((g - b) / d) % 6 : (mx == g ? (b - r) / d + 2 : (r - g) / d + 4);
  return [(hh * 60 + 360) % 360, s, l];
}

/// `#RRGGBB` from HSL (hue in degrees, s / l 0–1).
String rankFromHsl(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - c / 2;
  final List<double> p = h < 60
      ? [c, x, 0]
      : h < 120
          ? [x, c, 0]
          : h < 180
              ? [0, c, x]
              : h < 240
                  ? [0, x, c]
                  : h < 300
                      ? [x, 0, c]
                      : [c, 0, x];
  return _hex(p.map((v) => (v + m) * 255).toList());
}

/// Hue rotation by [deg] (saturation + lightness kept).
String rankSpin(String h, double deg) {
  final v = rankHsl(h);
  return rankFromHsl((v[0] + deg + 360) % 360, v[1], v[2]);
}

/// No pink / purple / violet in rank effects: hues 235–345°, light muted
/// reds (= dusty pink) and, for derived stops, the brand / road greens.
bool rankOffHue(String x) {
  final v = rankHsl(x);
  final hh = v[0], s = v[1], l = v[2];
  return (hh >= 235 && hh < 345) ||
      ((hh >= 345 || hh < 22) && s < 0.5 && l > 0.5) ||
      (hh >= 85 && hh < 160 && s > 0.12);
}

/// Tries ±deg, then ±deg/2; the colour itself when every spin is off-hue.
String rankSpinSafe(String h, double deg) {
  for (final d in [deg, -deg, deg / 2, -deg / 2]) {
    final x = rankSpin(h, d);
    if (!rankOffHue(x)) return x;
  }
  return h;
}

/// Moves [h] toward [to] in 2 % steps until contrast vs every bg ≥ target.
String rankFit(String h, List<String> bgs, double target, String to) {
  for (double t = 0; t <= 1.0001; t += 0.02) {
    final c = rankMix(h, to, t);
    if (bgs.every((bg) => rankContrast(c, bg) >= target)) return c;
  }
  return to;
}

/// Raises HSL lightness (hue + saturation kept, so the colour stays itself)
/// until contrast vs every bg ≥ target; falls back to [rankFit] → white.
String rankLiftL(String h, List<String> bgs, double target) {
  final v = rankHsl(h);
  for (var l = v[2]; l <= 0.97; l += 0.01) {
    final c = rankFromHsl(v[0], v[1], l);
    if (bgs.every((bg) => rankContrast(c, bg) >= target)) return c;
  }
  return rankFit(h, bgs, target, kRankWhite);
}

/// Partner stop at the same luminance as [y] (a hue shift, not a jump).
String rankMatchLum(String h, double y) {
  var n = 0;
  while ((rankLum(h) - y).abs() > 0.1 * y && n++ < 40) {
    h = rankMix(h, rankLum(h) > y ? kRankBlack : kRankWhite, 0.04);
  }
  return h;
}
