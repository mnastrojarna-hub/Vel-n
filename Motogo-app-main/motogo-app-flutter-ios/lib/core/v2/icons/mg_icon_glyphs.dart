import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import 'mg_icons.dart';

/// [MgIcons] names that are drawn from a Material Icons font glyph instead
/// of the hand-drawn 24-grid paths (owner, v5.0.1: the stick motorcycle
/// "looked like a child's drawing"). `two_wheeler_rounded` is a filled,
/// recognisable motorcycle at 15–64 px; `bike` (rides, SOS replacement,
/// "Moje jízdy", licence-only scan) also means a motorcycle, so it shares
/// it. The font ships with the app in both trees (`uses-material-design`).
const Map<String, IconData> kMgGlyphIcons = {
  MgIcons.moto: Icons.two_wheeler_rounded,
  MgIcons.bike: Icons.two_wheeler_rounded,
};

/// Optical fit of the wide, low motorcycle: its ink is ~20 × 11 of the
/// 24 em, so at 1.0 it reads half the height of its square neighbours; it
/// is drawn [kMgGlyphScale] × (ink ~22.4 wide, still inside the box) and
/// [kMgGlyphLift] × size higher, so the ink — not the em — is centred.
const double kMgGlyphScale = 1.12;
const double kMgGlyphLift = 0.04;

final Map<(int, double, Color), TextPainter> _glyphCache = {};

/// Paints [glyph] centred in [size] in [color] (cached per glyph, px and
/// colour — the menu repaints its icons on every tab change).
void paintMgGlyph(Canvas canvas, Size size, IconData glyph, Color color) {
  final box = size.shortestSide;
  final px = box * kMgGlyphScale;
  if (px <= 0) return;
  final key = (glyph.codePoint, px, color);
  var tp = _glyphCache[key];
  if (tp == null) {
    if (_glyphCache.length > 96) {
      for (final old in _glyphCache.values) {
        old.dispose();
      }
      _glyphCache.clear();
    }
    tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          inherit: false,
          color: color,
          fontSize: px,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          fontFamilyFallback: glyph.fontFamilyFallback,
        ),
      ),
    )..layout();
    _glyphCache[key] = tp;
  }
  tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2 - kMgGlyphLift * box));
}
