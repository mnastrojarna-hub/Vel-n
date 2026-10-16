// Rank theme (DESIGN_V22 §1): ramp parity with the generated table, contrast
// guarantees, no pink / violet anywhere, old-colour → ramp mapping.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/rank/rank_palette.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_row.dart';
import 'package:motogo_app/core/v2/rank/rank_solver.dart';
import 'package:motogo_app/core/v2/rank/rank_table.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';

String hx(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

List<int> allColours(RankRow r) => [
      r.hex, r.accentDark, r.accentGlass, r.uiDark, r.uiLight, r.chipBg, r.chipText,
      r.aura, r.glow, ...r.ctaFill, ...r.ctaEdge, ...r.ring,
      if (r.ring2 != null) r.ring2!,
      if (r.arc != null) r.arc!,
    ];

bool violetOrPink(int c) {
  final h = hx(c);
  final v = rankHsl(h);
  final rgb = [(c >> 16) & 255, (c >> 8) & 255, c & 255];
  final chroma = (rgb.reduce(math.max) - rgb.reduce(math.min)) / 255;
  return chroma > 0.12 && v[0] >= 232 && v[0] < 345;
}

void expectTokenContrast(RankRow r, String tag) {
  for (final s in r.ctaFill) {
    expect(rankContrast(hx(s), hx(r.ctaLabel)), greaterThanOrEqualTo(4.5),
        reason: '$tag CTA label on ${hx(s)}');
  }
  expect(rankContrast(hx(r.uiDark), '#0A1F14'), greaterThanOrEqualTo(3), reason: '$tag uiDark');
  expect(rankContrast(hx(r.accentDark), '#0E2A1C'), greaterThanOrEqualTo(4.5), reason: '$tag accent');
  expect(rankContrast(hx(r.chipText), hx(r.chipBg)), greaterThanOrEqualTo(4.5), reason: '$tag chip');
  expect(rankContrast('#FFFFFF', hx(r.aura)), greaterThanOrEqualTo(4.5), reason: '$tag aura');
  expect(rankContrast(hx(r.uiLight), '#FFFFFF'), greaterThanOrEqualTo(3), reason: '$tag uiLight');
  for (final c in allColours(r)) {
    expect(violetOrPink(c), isFalse, reason: '$tag ${hx(c)} is violet / pink');
  }
}

void main() {
  group('ramp table', () {
    test('20 levels, ramp colours, tiers by level', () {
      expect(kRankRampTable.length, 20);
      for (var l = 1; l <= 20; l++) {
        expect(hx(kRankRampTable[l - 1].hex), kRankRampHex[l - 1]);
        expect(kRankRampTable[l - 1].tier, rankTierOf(l));
      }
    });

    test('solver reproduces the table (each channel ±2)', () {
      for (var l = 1; l <= 20; l++) {
        final a = kRankRampTable[l - 1];
        final b = solveRankRow(l, kRankRampHex[l - 1]);
        final ca = allColours(a)..add(a.ctaLabel);
        final cb = allColours(b)..add(b.ctaLabel);
        expect(cb.length, ca.length, reason: 'level $l');
        for (var i = 0; i < ca.length; i++) {
          for (final sh in [16, 8, 0]) {
            final d = ((ca[i] >> sh) & 255) - ((cb[i] >> sh) & 255);
            expect(d.abs() <= 2, isTrue, reason: 'level $l colour $i ${hx(ca[i])} vs ${hx(cb[i])}');
          }
        }
        expect(b.ctaAngle, a.ctaAngle);
        expect(b.ringKind, a.ringKind);
        expect(b.glowAlpha, a.glowAlpha);
      }
    });

    test('contrast + no violet/pink on every level', () {
      for (var l = 1; l <= 20; l++) {
        expectTokenContrast(kRankRampTable[l - 1], 'L$l');
      }
    });

    test('solver keeps manual Velín colours safe', () {
      const manual = ['#7C3AED', '#FF00AA', '#123456', '#FAFAFA', '#00FF00', '#8B4513', '#222222'];
      for (final hex in manual) {
        for (final l in [2, 7, 12, 15, 17, 18, 19, 20]) {
          final r = solveRankRow(l, hex);
          for (final s in r.ctaFill) {
            expect(rankContrast(hx(s), hx(r.ctaLabel)), greaterThanOrEqualTo(4.5),
                reason: 'L$l $hex label');
          }
          expect(rankContrast(hx(r.accentDark), '#0E2A1C'), greaterThanOrEqualTo(4.5));
          expect(rankContrast(hx(r.chipText), hx(r.chipBg)), greaterThanOrEqualTo(4.5));
          expect(rankContrast('#FFFFFF', hx(r.aura)), greaterThanOrEqualTo(4.5));
        }
      }
    });
  });

  group('colour resolution without SQL', () {
    test('old seed colours map to the ramp', () {
      for (var l = 1; l <= 20; l++) {
        expect(resolveRankHex(l, kRankOldSeedHex[l - 1]), kRankRampHex[l - 1]);
        expect(resolveRankHex(l, kRankOldSeedHex[l - 1].toLowerCase()), kRankRampHex[l - 1]);
      }
    });

    test('unapplied v2.1 draft maps to the ramp', () {
      kRankV21DraftHex.forEach((l, hex) => expect(resolveRankHex(l, hex), kRankRampHex[l - 1]));
    });

    test('null / invalid → ramp, manual edit kept, level 0 → brand', () {
      expect(resolveRankHex(5, null), kRankRampHex[4]);
      expect(resolveRankHex(5, 'zelená'), kRankRampHex[4]);
      expect(resolveRankHex(5, '#abcdef'), '#ABCDEF');
      expect(resolveRankHex(0, '#123456'), kRankBrandHex);
      expect(RankTokens.forLevel(0).isBrand, isTrue);
      expect(RankTokens.forLevel(0).hex.toARGB32(), 0xFF74FB71);
    });

    test('tokens from the table for ramp colours, solver for manual ones', () {
      expect(identical(RankTokens.forLevel(13, '#6366F1').row, kRankRampTable[12]), isTrue);
      expect(RankTokens.forLevel(13, '#123456').row.hex, 0xFF123456);
    });
  });

  group('tokens', () {
    test('steps inside the tier', () {
      expect(RankTokens.forLevel(3).step, 3);
      expect(RankTokens.forLevel(3).steps, 5);
      expect(RankTokens.forLevel(6).step, 1);
      expect(RankTokens.forLevel(16).step, 7);
      expect(RankTokens.forLevel(16).steps, 7);
      expect(RankTokens.forLevel(20).steps, 1);
      expect(RankTokens.forLevel(18).glyph, RankGlyph.crown);
      expect(RankTokens.forLevel(20).glyph, RankGlyph.laurel);
    });

    test('glow grows with the step, pulse adds a ring', () {
      final a = RankTokens.forLevel(1).ctaGlow();
      final b = RankTokens.forLevel(5).ctaGlow();
      expect(b.first.blurRadius, greaterThan(a.first.blurRadius));
      expect(RankTokens.forLevel(10).ctaGlow(0.5).length,
          greaterThan(RankTokens.forLevel(10).ctaGlow().length));
    });

    test('arc %', () {
      expect(rankArcPct(3, 5, 1), 50);
      expect(rankArcPct(3, null, 2), 4);
      expect(rankArcPct(20, 40, null), 100);
      expect(rankArcPct(0, null, null), 0);
    });
  });
}
