// Dart port of appdesign/research/rankTheme.js (+ the gen/gen.js post-
// processing) — computes the rank token row for ANY colour, so a level whose
// colour the owner edits in Velín stays contrast-safe and never turns pink /
// violet. For the 20 ramp colours it reproduces `kRankRampTable` (unit test),
// incl. the painted-token distinctness picks (rank_seeds.dart, r2 2026-10-29).
import 'dart:math' as math;

import 'rank_color_math.dart';
import 'rank_palette.dart' show kRankRampHex;
import 'rank_row.dart';
import 'rank_seeds.dart';

export 'rank_color_math.dart'
    show rankLum, rankContrast, rankMix, rankHsl, rankFit, rankLiftL, rankOffHue;

const _neon = '#74FB71', _neonHi = '#8DFF86', _neonLo = '#37CF63';
const _onNeon = '#08230F', _night = '#0A1F14', _panel = '#0E2A1C';
const _glowStop = '#24563B', _inkDark = '#1A2E22', _page = '#DFF0EC';
const _card = '#FFFFFF', _white = kRankWhite, _black = kRankBlack;
const _trim = '#F3D27E';
const _legend = ['#FFE27A', '#FFD700', '#FF9A1F', '#FF6B00'];
const _inkWarm = '#1A1405', _inkCool = '#0B1512', _inkLegend = '#241A06';
const _inkNavy = '#0A1F33', _inkOnyx = '#14100A';

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

bool _passes(String c, List<String> bgs, double t) => bgs.every((bg) => rankContrast(c, bg) >= t);

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
  final seeded = lv >= 1 && c == kRankRampHex[lv - 1];
  final rr = rankRgb(c);
  final grey = (rr.reduce(math.max) - rr.reduce(math.min)) / 255 < 0.12;
  final hue = rankHsl(c)[0];
  final red = (hue < 20 || hue > 340) && !grey;
  final up = red ? '#FFCF99' : _white;
  String lift(String h, List<String> bgs, double target) =>
      (red && bgs.any((bg) => rankContrast(h, bg) < target)) ? _trim : rankFit(h, bgs, target, up);
  final pickDark = seeded ? kRankAccDark[lv] : null;
  final accentDark = (pickDark != null && _passes(pickDark, [_panel, _inkDark], 4.5))
      ? pickDark
      : lift(c, [_panel, _inkDark], 4.5);
  final accentLight = rankFit(c, [_page, _card], 4.55, _black);
  final uiLight = rankFit(c, [_card], 3.0, _black);
  final uiDark = rankFit(c, [_panel], 3.0, up);

  final glowHex = (seeded && kRankGlow[lv] != null)
      ? kRankGlow[lv]!
      : (lv <= 1)
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

  // primary CTA (always on a dark surface) — label ≥ 4.5 : 1 on every stop
  List<String> stops;
  String label;
  List<String>? edge;
  double angle = 135;
  if (lv == 0 || tier == RankTier.road) {
    // brand neon only tints the first third, RANK colour carries the rest
    label = _onNeon;
    stops = lv == 0
        ? _solve([_neonHi, _neonLo], label, _white)
        : _solve(List.generate(4, (i) => rankMix(i < 2 ? _neonHi : _neonLo, c, kRankRoadW[i])), label, _white);
    if (lv > 0) edge = [rankMix(c, _white, 0.5), c, c, rankMix(c, _black, 0.15)];
  } else if (tier == RankTier.metal) {
    label = grey ? _inkCool : _inkWarm;
    angle = 115;
    final fixed = seeded ? kRankCtaStops[lv] : null;
    stops = _solve(
        fixed ?? [rankMix(c, _white, 0.55), rankMix(c, _white, 0.18), c, rankMix(c, _black, 0.10)], label, _white);
    edge = [rankMix(c, _white, 0.75), rankMix(c, _black, 0.20)];
  } else if (tier == RankTier.jewel) {
    final spinBy = seeded ? kRankCtaSpin[lv] : null;
    final sp = (spinBy != null && !rankOffHue(rankSpin(c, spinBy))) ? rankSpin(c, spinBy) : rankSpinSafe(c, 24);
    final base = [c, rankMatchLum(sp, rankLum(c))];
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
      label = '#7F1D1D'; // ivory-champagne foil + crimson label, crimson–gold frame
      stops = _solve(kRankCtaStops[17]!, label, _white);
      edge = ['#D42020', '#FDE68A', '#B91C1C'];
    } else if (lv == 18) {
      label = _inkOnyx;
      stops = _solve(kRankCtaStops[18]!, label, _white);
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

  // ring around logo / avatar / PROFIL tab (drawn on dark)
  RankRingKind kind;
  List<String> ring;
  String? ring2;
  final ringStops = seeded ? kRankRingStops[lv] : null;
  if (lv == 0 || tier == RankTier.road) {
    kind = RankRingKind.solid;
    ring = [c];
  } else if (tier == RankTier.metal) {
    kind = RankRingKind.metal;
    ring = ringStops != null
        ? [...ringStops, ringStops[0]]
        : [rankMix(c, _white, 0.6), c, rankMix(c, _black, 0.25), rankMix(c, _white, 0.6)];
  } else if (tier == RankTier.jewel) {
    // every segment ≥ 3.2 : 1 on the dark header; partners = hue shifts at the same luminance
    kind = RankRingKind.jewel;
    final u = rankFit(uiDark, [_panel], 3.2, up), y = rankLum(u);
    final p = (seeded ? kRankRingSpin[lv] : null) ?? const [24.0, -18.0];
    final q = p.map((d) {
      var x = rankSpin(u, d);
      if (rankOffHue(x)) x = rankSpinSafe(u, d);
      return rankFit(rankMatchLum(x, y), [_panel], 3.2, _white);
    }).toList();
    ring = [u, q[0], u, q[1], u];
  } else if (tier == RankTier.vip) {
    kind = RankRingKind.vip;
    if (ringStops != null) {
      ring = [...ringStops]; // VIP Gold: flat brushed gold
      ring2 = '#FFF1C2';
    } else {
      final d0 = rankContrast(c, _panel) >= 3.2 ? c : rankFit(c, [_panel], 3.2, up);
      final h0 = rankHsl(d0)[0];
      final hi = (h0 < 20 || h0 > 340) ? '#FFE08A' : _white;
      ring = [d0, rankMix(d0, hi, 0.3), d0];
      ring2 = lv == 18 ? '#FFF1C2' : '#D4AF37';
    }
  } else {
    kind = RankRingKind.legend;
    ring = [..._legend, _legend[0]];
  }

  final chipBg = rankMix(_panel, c, 0.16);
  final pickChip = seeded ? kRankChipText[lv] : null;
  final chipText = (pickChip != null && _passes(pickChip, [chipBg, _inkDark], 4.5))
      ? pickChip
      : _passes(accentDark, [chipBg, _inkDark], 4.5)
          ? accentDark
          : red
              ? lift(accentDark, [chipBg, _inkDark], 4.5)
              : rankLiftL(accentDark, [chipBg, _inkDark], 4.5);
  const auraMix = [0.25, 0.32, 0.38, 0.42, 0.50];
  final aura = rankFit(rankMix(_glowStop, glowHex, auraMix[ti]), [_white], 4.6, _night);

  // gen.js: glass-safe accent + arc lifted against its track over the hero.
  final glass = rankMix(rankMix(aura, _panel, 0.75), _white, 0.06);
  final track = rankMix(rankMix(aura, _panel, 0.75), _white, 0.18);
  bool isRed(String h) {
    final v = rankHsl(h);
    return (v[0] < 20 || v[0] > 340) && v[1] > 0.25;
  }

  final pickGlass = seeded ? kRankAccGlass[lv] : null;
  final accG = (pickGlass != null && rankContrast(pickGlass, glass) >= 4.6)
      ? pickGlass
      : rankContrast(accentDark, glass) >= 4.6
          ? accentDark
          : (isRed(accentDark) ? _trim : rankLiftL(accentDark, [glass], 4.6));
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
