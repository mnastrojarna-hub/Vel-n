// Contrast helper of the v2 safeguard tests (soupis pojistek 2026-11-12):
// every Text under a finder must be readable on the surface it really sits
// on — the first OPAQUE ancestor fill (Container / DecoratedBox colour or
// gradient, ColoredBox, Material). Translucent tints are skipped, so a
// "6 % white" tile on a light page is judged against the light page.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG contrast ratio of two opaque colours.
double contrastOf(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color? _opaque(Decoration? d) {
  if (d is BoxDecoration) {
    if (d.color != null && d.color!.a >= 0.99) return d.color;
    final g = d.gradient;
    if (g != null && g.colors.isNotEmpty && g.colors.first.a >= 0.99) return g.colors.first;
  }
  return null;
}

/// The surface colour behind [e] ([page] when nothing opaque is found).
Color surfaceBehind(Element e, Color page) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Container) c = (w.color != null && w.color!.a >= 0.99) ? w.color : _opaque(w.decoration);
    if (w is DecoratedBox) c = _opaque(w.decoration);
    if (w is ColoredBox && w.color.a >= 0.99) c = w.color;
    if (w is Material && w.type != MaterialType.transparency && w.color != null && w.color!.a >= 0.99) c = w.color;
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  return found ?? page;
}

/// Every Text under [of] with its contrast on the surface behind it.
List<(String, double)> textContrasts(WidgetTester t, Finder of, Color page) {
  final out = <(String, double)>[];
  for (final e in find.descendant(of: of, matching: find.byType(Text)).evaluate()) {
    final w = e.widget as Text;
    final style = DefaultTextStyle.of(e).style.merge(w.style);
    final fg = style.color ?? const Color(0xFF000000);
    final bg = surfaceBehind(e, page);
    final fgSolid = Color.alphaBlend(fg, bg);
    out.add((w.data ?? w.textSpan?.toPlainText() ?? '', contrastOf(fgSolid, bg)));
  }
  return out;
}

/// Fails with the unreadable texts listed.
/// [skip]: texts painted by a shader (the multicolour Google "G" badge).
void expectReadable(WidgetTester t, Finder of, Color page, {double min = 4.5, Set<String> skip = const {}}) {
  final bad = [
    for (final (s, c) in textContrasts(t, of, page))
      if (c < min && s.trim().isNotEmpty && !skip.contains(s)) '"$s" ${c.toStringAsFixed(2)}:1'
  ];
  expect(bad, isEmpty, reason: 'texts below $min:1 on their real surface');
}
