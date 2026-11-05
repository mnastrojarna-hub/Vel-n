import 'package:flutter/painting.dart';

/// Result of the bottom-nav label fit (DESIGN_V2 §4.1, = `nav.js`).
class V2NavFit {
  /// Labels to draw (a short form where the long one would collide).
  final List<String> labels;

  /// Font size of the whole row (11 normally, 10 = last-resort rung).
  final double px;

  /// 1 = user size, 2 = row clamped to 11 px, 3 = row at 10 px.
  final int rung;

  /// Smallest gap between two neighbouring labels / to the bar edge.
  final double gap;
  final double edge;
  final bool ok;
  final List<bool> shortened;

  const V2NavFit({
    required this.labels,
    required this.px,
    required this.rung,
    required this.gap,
    required this.edge,
    required this.ok,
    required this.shortened,
  });

  /// The row is drawn smaller than the user's size or with a short form →
  /// long-press shows the full label.
  bool get compromised => rung > 1 || shortened.any((s) => s);
}

/// Minimum gap between neighbouring labels and to the bar edges.
const double kV2NavGap = 6, kV2NavEdge = 4;

/// No-overlap ladder: labels are centred in 5 equal columns; real gaps are
/// `col − (wᵢ + wᵢ₊₁) / 2` (≥ 6 px) and edge gaps `(col − w) / 2` (≥ 4 px).
/// Rung ① the user's size (11 × scale, max 1.15) with a short form only for a
/// label in a failing spot → ② the row clamped to 11 px, short forms again
/// only where needed → ③ the row at 10 px. Labels are NEVER ellipsized,
/// wrapped or scaled by `FittedBox`. [measure] returns the label width at a
/// font size (TextPainter in the app; table widths in unit tests).
V2NavFit v2NavFit({
  required List<String> full,
  required List<String?> short,
  required double width,
  required double Function(String label, double px) measure,
  double scale = 1,
}) {
  assert(full.length == 5 && short.length == 5);
  final col = width / 5;
  final s = scale.clamp(0.5, 1.15);
  final px0 = 11 * s;
  final ladder = [px0, px0 < 11 ? px0 : 11.0, px0 < 10 ? px0 : 10.0];

  (double, double) gaps(List<double> w) {
    var g = double.infinity;
    for (var i = 0; i < 4; i++) {
      final x = col - (w[i] + w[i + 1]) / 2;
      if (x < g) g = x;
    }
    final e = ((col - w[0]) < (col - w[4]) ? (col - w[0]) : (col - w[4])) / 2;
    return (g, e);
  }

  V2NavFit fit(double px, int rung) {
    final lbl = List<String>.from(full);
    final w = [for (final l in lbl) measure(l, px)];
    final sh = List<bool>.filled(5, false);
    for (var pass = 0; pass < 5; pass++) {
      final cand = <int>[];
      for (var i = 0; i < 4; i++) {
        if (col - (w[i] + w[i + 1]) / 2 < kV2NavGap) {
          cand.addAll(w[i] >= w[i + 1] ? [i, i + 1] : [i + 1, i]);
        }
      }
      if ((col - w[0]) / 2 < kV2NavEdge) cand.add(0);
      if ((col - w[4]) / 2 < kV2NavEdge) cand.add(4);
      final j = cand.cast<int?>().firstWhere(
            (x) => short[x!] != null && short[x] != full[x] && !sh[x],
            orElse: () => null,
          );
      if (j == null) break;
      lbl[j] = short[j]!;
      w[j] = measure(lbl[j], px);
      sh[j] = true;
    }
    final (g, e) = gaps(w);
    return V2NavFit(
      labels: lbl,
      px: px,
      rung: rung,
      gap: g,
      edge: e,
      ok: g >= kV2NavGap && e >= kV2NavEdge,
      shortened: sh,
    );
  }

  V2NavFit? last;
  for (var r = 0; r < ladder.length; r++) {
    last = fit(ladder[r], r + 1);
    if (last.ok) return last;
  }
  return last!;
}

/// TextPainter measure for [v2NavFit] with the style the nav really draws
/// (w800 — the active weight, the widest). Widths are cached app-wide per
/// (style, label, px): the shell rebuilds on every route change and poll, so
/// the nav must not re-lay-out up to 15 TextPainters each time.
double Function(String, double) v2NavMeasure(TextStyle base) {
  _watchFonts();
  final style = base.copyWith(fontWeight: FontWeight.w800);
  return (label, px) {
    final key = (style, label, px);
    final hit = _measureCache[key];
    if (hit != null) return hit;
    if (_measureCache.length > 400) _measureCache.clear();
    final tp = TextPainter(
      text: TextSpan(text: label, style: style.copyWith(fontSize: px)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return _measureCache[key] = w;
  };
}

final Map<(TextStyle, String, double), double> _measureCache = {};
final Map<(String, String, double, double, TextStyle), V2NavFit> _fitCache = {};
bool _fontsWatched = false;

/// A font loaded later (Montserrat from the network / assets) changes the
/// widths → forget every cached measurement.
void _watchFonts() {
  if (_fontsWatched) return;
  _fontsWatched = true;
  try {
    PaintingBinding.instance.systemFonts.addListener(() {
      _measureCache.clear();
      _fitCache.clear();
    });
  } catch (_) {}
}

/// [v2NavFit] memoised on its inputs (labels, width, scale, style).
V2NavFit v2NavFitCached({
  required List<String> full,
  required List<String?> short,
  required double width,
  required TextStyle base,
  double scale = 1,
}) {
  final key = (full.join('\u0001'), short.join('\u0001'), width, scale, base);
  final hit = _fitCache[key];
  if (hit != null) return hit;
  if (_fitCache.length > 64) _fitCache.clear();
  return _fitCache[key] = v2NavFit(full: full, short: short, width: width, measure: v2NavMeasure(base), scale: scale);
}
