// Rank ramp: every PAINTED token stays distinct (DESIGN_V22 §1.1, board
// "painted-token distinctness", tools2/rkcmp.py): CIEDE2000 ≥ 10 for every
// pair of levels and ≥ 12 for neighbours — rank text on dark, glass accent,
// chip text, glow and the CTA fill (mean ΔE of the 4 stops).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/rank/rank_palette.dart';
import 'package:motogo_app/core/v2/rank/rank_row.dart';
import 'package:motogo_app/core/v2/rank/rank_solver.dart';
import 'package:motogo_app/core/v2/rank/rank_table.dart';

List<double> _lab(int c) {
  double f(int v) {
    final x = v / 255;
    return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = f((c >> 16) & 255), g = f((c >> 8) & 255), b = f(c & 255);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double ff(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return [116 * ff(y) - 16, 500 * (ff(x) - ff(y)), 200 * (ff(y) - ff(z))];
}

double _deg(double r) => r * 180 / math.pi;
double _rad(double d) => d * math.pi / 180;

/// CIEDE2000 colour difference of two ARGB colours.
double deltaE00(int c1, int c2) {
  final p = _lab(c1), q = _lab(c2);
  final c1a = math.sqrt(p[1] * p[1] + p[2] * p[2]), c2a = math.sqrt(q[1] * q[1] + q[2] * q[2]);
  final cb = (c1a + c2a) / 2;
  final g = 0.5 * (1 - math.sqrt(math.pow(cb, 7) / (math.pow(cb, 7) + math.pow(25, 7))));
  final a1 = (1 + g) * p[1], a2 = (1 + g) * q[1];
  final c1p = math.sqrt(a1 * a1 + p[2] * p[2]), c2p = math.sqrt(a2 * a2 + q[2] * q[2]);
  final h1 = _deg(math.atan2(p[2], a1)) % 360, h2 = _deg(math.atan2(q[2], a2)) % 360;
  final dl = q[0] - p[0], dc = c2p - c1p;
  var dh = h2 - h1;
  if (c1p * c2p == 0) {
    dh = 0;
  } else if (dh > 180) {
    dh -= 360;
  } else if (dh < -180) {
    dh += 360;
  }
  final dH = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dh / 2));
  final lb = (p[0] + q[0]) / 2, cbp = (c1p + c2p) / 2;
  var hb = (h1 - h2).abs() > 180 ? (h1 + h2 + 360) / 2 : (h1 + h2) / 2;
  if (c1p * c2p == 0) hb = h1 + h2;
  final t = 1 -
      0.17 * math.cos(_rad(hb - 30)) +
      0.24 * math.cos(_rad(2 * hb)) +
      0.32 * math.cos(_rad(3 * hb + 6)) -
      0.2 * math.cos(_rad(4 * hb - 63));
  final sl = 1 + 0.015 * (lb - 50) * (lb - 50) / math.sqrt(20 + (lb - 50) * (lb - 50));
  final sc = 1 + 0.045 * cbp, sh = 1 + 0.015 * cbp * t;
  final dt = 30 * math.exp(-math.pow((hb - 275) / 25, 2));
  final rc = 2 * math.sqrt(math.pow(cbp, 7) / (math.pow(cbp, 7) + math.pow(25, 7)));
  final rt = -math.sin(_rad(2 * dt)) * rc;
  return math.sqrt(math.pow(dl / sl, 2) + math.pow(dc / sc, 2) + math.pow(dH / sh, 2) + rt * (dc / sc) * (dH / sh));
}

final _tokens = <String, double Function(RankRow, RankRow)>{
  'rank text on dark': (a, b) => deltaE00(a.accentDark, b.accentDark),
  'glass accent': (a, b) => deltaE00(a.accentGlass, b.accentGlass),
  'chip text': (a, b) => deltaE00(a.chipText, b.chipText),
  'glow': (a, b) => deltaE00(a.glow, b.glow),
  'CTA fill': (a, b) => List.generate(4, (i) => deltaE00(a.ctaFill[i], b.ctaFill[i])).reduce((x, y) => x + y) / 4,
};

void main() {
  test('CIEDE2000 sanity (same formula as tools2/rkcmp.py)', () {
    expect(deltaE00(0xFF336699, 0xFF336699), 0);
    expect(deltaE00(0xFF000000, 0xFFFFFFFF), closeTo(100, 0.5));
  });

  for (final rows in {
    'table': kRankRampTable,
    'solver': [for (var l = 1; l <= 20; l++) solveRankRow(l, kRankRampHex[l - 1])],
  }.entries) {
    test('${rows.key}: painted tokens ΔE00 ≥ 10 for all pairs, ≥ 12 for neighbours', () {
      final bad = <String>[];
      _tokens.forEach((name, de) {
        for (var i = 1; i <= 20; i++) {
          for (var j = i + 1; j <= 20; j++) {
            final d = de(rows.value[i - 1], rows.value[j - 1]);
            final min = j - i == 1 ? 12.0 : 10.0;
            if (d < min) bad.add('$name $i↔$j ${d.toStringAsFixed(1)}');
          }
        }
      });
      expect(bad, isEmpty);
    });
  }

  test('Silnice 1–5 CTA is rank-coloured, not the guest neon', () {
    final guest = solveRankRow(0, kRankBrandHex);
    // Startér was the pure guest neon before r2 (board: sage #9BD19C → #A3B8A8)
    expect(_tokens['CTA fill']!(kRankRampTable[0], guest), greaterThan(12));
    for (var l = 1; l <= 5; l++) {
      final r = kRankRampTable[l - 1];
      expect(r.ctaFill[2], r.hex, reason: 'L$l CTA second half = rank colour');
      expect(r.ctaEdge[1], r.hex, reason: 'L$l edge carries the rank colour');
    }
  });

  test('seeded picks apply only to the ramp colour (Velín edit → solver)', () {
    expect(solveRankRow(17, kRankRampHex[16]).accentDark, 0xFFF6E7C9);
    expect(solveRankRow(17, '#C81E1E').accentDark, isNot(0xFFF6E7C9));
    expect(solveRankRow(14, '#5A88D0').glow, isNot(0xFF118BDF));
  });
}
