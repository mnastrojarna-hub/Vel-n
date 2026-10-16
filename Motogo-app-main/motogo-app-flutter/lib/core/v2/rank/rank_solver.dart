// Dart port of appdesign/research/rankTheme.js (+ the gen/gen.js post-
// processing) — computes the rank token row for ANY colour, so a level whose
// colour the owner edits in Velín stays contrast-safe and never turns pink /
// violet. For the 20 ramp colours it reproduces `kRankRampTable` (unit test).
import 'dart:math' as math;

import 'rank_row.dart';

const _neon = '#74FB71', _neonHi = '#8DFF86', _neonLo = '#37CF63';
const _onNeon = '#08230F', _night = '#0A1F14', _panel = '#0E2A1C';
const _glowStop = '#24563B', _inkDark = '#1A2E22', _page = '#DFF0EC';
const _card = '#FFFFFF', _white = '#FFFFFF', _black = '#000000';
const _trim = '#F3D27E';
const _legend = ['#FFE27A', '#FFD700', '#FF9A1F', '#FF6B00'];
const _inkWarm = '#1A1405', _inkCool = '#0B1512', _inkLegend = '#241A06';
const _inkNavy = '#0A1F33', _inkOnyx = '#14100A';

List<int> _rgb(String h) =>
    [1, 3, 5].map((i) => int.parse(h.substring(i, i + 2), radix: 16)).toList();

String _hex(List<double> c) =>
    '#${c.map((v) => v.round().clamp(0, 255).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

double _lin(int v) {
  final x = v / 255;
  return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
}

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

String _fromHsl(double h, double s, double l) {
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

String _spin(String h, double deg) {
  final v = rankHsl(h);
  return _fromHsl((v[0] + deg + 360) % 360, v[1], v[2]);
}

bool _offHue(String x) {
  final v = rankHsl(x);
  final hh = v[0], s = v[1], l = v[2];
  return (hh >= 235 && hh < 345) ||
      ((hh >= 345 || hh < 22) && s < 0.5 && l > 0.5) ||
      (hh >= 85 && hh < 160 && s > 0.12);
}

String _spinSafe(String h, double deg) {
  for (final d in [deg, -deg, deg / 2, -deg / 2]) {
    final x = _spin(h, d);
    if (!_offHue(x)) return x;
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

String _matchLum(String h, double y) {
  var n = 0;
  while ((rankLum(h) - y).abs() > 0.1 * y && n++ < 40) {
    h = rankMix(h, rankLum(h) > y ? _black : _white, 0.04);
  }
  return h;
}

double _minCr(List<String> stops, String text) =>
    stops.map((s) => rankContrast(s, text)).reduce(math.min);

List<String> _solve(List<String> stops, String label, String to) {
  var n = 0;
  while (_minCr(stops, label) < 4.5 && n++ < 50) {
    stops = stops.map((s) => rankMix(s, to, 0.04)).toList();
  }
  return stops;
}

List<String> _norm4(List<String> s) {
  if (s.length >= 4) return s.sublist(0, 4);
  if (s.length == 3) {
    return [s[0], rankMix(s[0], s[1], 2 / 3), rankMix(s[1], s[2], 1 / 3), s[2]];
  }
  if (s.length == 2) {
    return [s[0], rankMix(s[0], s[1], 1 / 3), rankMix(s[0], s[1], 2 / 3), s[1]];
  }
  return [s[0], s[0], s[0], s[0]];
}

/// Tier of a level (0 = guest / brand → road).
RankTier rankTierOf(int level) {
  if (level >= 20) return RankTier.legend;
  if (level >= 17) return RankTier.vip;
  if (level >= 10) return RankTier.jewel;
  if (level >= 6) return RankTier.metal;
  return RankTier.road;
}

int _c(String h) => 0xFF000000 | int.parse(h.substring(1), radix: 16);

/// Full token row for [level] (0–20) drawn in [colorHex] (`#RRGGBB`).
RankRow solveRankRow(int level, String colorHex) {
  final lv = level.clamp(0, 20);
  final c = colorHex.toUpperCase();
  final tier = rankTierOf(lv);
  final ti = tier.index;
  final rr = _rgb(c);
  final chroma = (rr.reduce(math.max) - rr.reduce(math.min)) / 255;
  final grey = chroma < 0.12;
  final hue = rankHsl(c)[0];
  final red = (hue < 20 || hue > 340) && !grey;
  final up = red ? '#FFCF99' : _white;
  String lift(String h, List<String> bgs, double target) =>
      (red && bgs.any((bg) => rankContrast(h, bg) < target)) ? _trim : rankFit(h, bgs, target, up);
  final accentDark = lift(c, [_panel, _inkDark], 4.5);
  final accentLight = rankFit(c, [_page, _card], 4.55, _black);
  final uiLight = rankFit(c, [_card], 3.0, _black);
  final uiDark = rankFit(c, [_panel], 3.0, up);

  final glowHex = (lv <= 1)
      ? _neon
      : lv == 20
          ? '#FF8C00'
          : grey
              ? rankMix(c, '#BFD9FF', 0.35)
              : rankLum(c) < 0.2
                  ? rankMix(c, red ? '#FF7A45' : '#9FD0FF', 0.3)
                  : c;
  const alphas = [0.50, 0.55, 0.58, 0.62, 0.66];
  const blurs = [22.0, 26.0, 28.0, 30.0, 34.0];
  const haloA = [0.0, 0.12, 0.16, 0.20, 0.24];
  const haloB = [0.0, 40.0, 44.0, 48.0, 56.0];
  const pulse = [7.0, 8.0, 9.0, 9.0, 10.0];

  List<String> stops;
  String label;
  List<String>? edge;
  double angle = 135;
  if (lv == 0 || tier == RankTier.road) {
    label = _onNeon;
    stops = _solve([_neonHi, lv > 1 ? rankMix(_neonLo, c, 0.5) : _neonLo], label, _white);
  } else if (tier == RankTier.metal) {
    label = grey ? _inkCool : _inkWarm;
    angle = 115;
    stops = _solve([rankMix(c, _white, 0.55), rankMix(c, _white, 0.18), c, rankMix(c, _black, 0.10)], label, _white);
    edge = [rankMix(c, _white, 0.75), rankMix(c, _black, 0.20)];
  } else if (tier == RankTier.jewel) {
    final base = [c, _matchLum(_spinSafe(c, 24), rankLum(c))];
    final ink = rankHsl(c)[0] < 100 ? _inkWarm : _inkNavy;
    final ice = rankContrast(c, ink) >= rankContrast(c, _white);
    label = ice ? ink : _white;
    stops = _solve(base, label, ice ? _white : _black);
    edge = [
      rankFit(rankMix(stops[0], _white, 0.45), [_night], 3, _white),
      rankFit(rankMix(stops[1], _white, 0.25), [_night], 3, _white),
    ];
  } else if (tier == RankTier.vip) {
    if (lv == 17) {
      label = '#7F1D1D';
      stops = _solve(['#FFFBF2', '#FBEEDB', '#F3DEC0'], label, _white);
      edge = ['#EF4444', '#FDE68A', '#B91C1C'];
    } else if (lv == 18) {
      label = _inkOnyx;
      stops = _solve(['#F7E9B8', '#E6C869', c, '#B8932A'], label, _white);
      edge = ['#FFF6D6', '#8C6A12'];
    } else {
      label = _inkOnyx;
      stops = _solve(['#FFFFFF', '#F1F5F9', '#DCE3EC'], label, _white);
      edge = ['#E2E8F0', '#BAE6FD', '#BBF7D0', '#FDE68A'];
    }
  } else {
    label = _inkLegend;
    stops = _solve(_legend, label, _white);
    edge = ['#FFF4D6', '#FFB000'];
  }
  final b = _norm4(stops);
  final e = _norm4(edge ?? [rankMix(b[0], _white, 0.5), b[0], b[3], b[3]]);

  RankRingKind kind;
  List<String> ring;
  String? ring2;
  if (lv == 0 || tier == RankTier.road) {
    kind = RankRingKind.solid;
    ring = [c];
  } else if (tier == RankTier.metal) {
    kind = RankRingKind.metal;
    ring = [rankMix(c, _white, 0.6), c, rankMix(c, _black, 0.25), rankMix(c, _white, 0.6)];
  } else if (tier == RankTier.jewel) {
    kind = RankRingKind.jewel;
    ring = [c, _spinSafe(c, 24), c, _spinSafe(c, -18), c];
  } else if (tier == RankTier.vip) {
    kind = RankRingKind.vip;
    final h0 = rankHsl(c)[0];
    final hi = (h0 < 20 || h0 > 340) ? '#FFE08A' : _white;
    ring = [c, rankMix(c, hi, 0.3), c];
    ring2 = lv == 18 ? '#FFF1C2' : '#D4AF37';
  } else {
    kind = RankRingKind.legend;
    ring = [..._legend, _legend[0]];
  }

  final chipBg = rankMix(_panel, c, 0.16);
  final chipText = lift(c, [chipBg, _inkDark], 4.5);
  const auraMix = [0.25, 0.32, 0.38, 0.42, 0.50];
  final aura = rankFit(rankMix(_glowStop, glowHex, auraMix[ti]), [_white], 4.6, _night);

  // gen.js: glass-safe accent + arc lifted against its track over the hero.
  final glass = rankMix(rankMix(aura, _panel, 0.75), _white, 0.06);
  final track = rankMix(rankMix(aura, _panel, 0.75), _white, 0.18);
  bool isRed(String h) {
    final v = rankHsl(h);
    return (v[0] < 20 || v[0] > 340) && v[1] > 0.25;
  }

  final accG = rankContrast(accentDark, glass) >= 4.6
      ? accentDark
      : (isRed(accentDark) ? _trim : rankFit(accentDark, [glass], 4.6, _white));
  String? arc;
  if (lv > 0 && lv < 20) {
    final a0 = rankMix(uiDark, up, 0.2);
    arc = rankContrast(a0, track) >= 3.2 ? a0 : rankFit(a0, [track], 3.2, isRed(a0) ? '#FFCF99' : _white);
  }

  return RankRow(
    tier,
    _c(c),
    _c(accentDark),
    _c(accG),
    _c(accentLight),
    _c(uiDark),
    _c(uiLight),
    _c(chipBg),
    _c(chipText),
    _c(aura),
    _c(glowHex),
    alphas[ti],
    blurs[ti],
    haloA[ti],
    haloB[ti],
    pulse[ti],
    b.map(_c).toList(),
    angle,
    _c(label),
    e.map(_c).toList(),
    kind,
    ring.map(_c).toList(),
    ring2 == null ? null : _c(ring2),
    arc == null ? null : _c(arc),
  );
}
