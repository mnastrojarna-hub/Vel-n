// v5.0.1 bottom menu + motorcycle glyph (owner: "víc svítivě zelené, aby
// bylo víc wow, jako to původní"; "ikonka motorky jak když to kreslilo
// pětileté dítě"): the active pill is the brand neon whatever the rank, its
// halo breathes only with motion on, the Profil rank ring keeps a night
// disc on the pill, a too-wide active label steps down, and MgIcons.moto /
// bike paint the font glyph, not the old stick paths.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_fx.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/icons/mg_icon_glyphs.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';

import '../render/cases_v501_core.dart' show loadMaterialIconsFont;
import '../support/v2_harness.dart';

Widget _bar(int active, {RankTokens? rank, int badge = 0}) => Align(
      alignment: Alignment.bottomCenter,
      child: V2NavBar(activeIndex: active, onTap: (_) {}, rank: rank, arcPct: 60, profileBadge: badge),
    );

BoxDecoration _pill(WidgetTester t) =>
    t.widget<DecoratedBox>(find.byKey(const ValueKey('v2-nav-pill'))).decoration as BoxDecoration;

/// Counts what a painter draws (paths vs text paragraphs).
class _CountCanvas implements Canvas {
  int paths = 0;
  int paragraphs = 0;
  @override
  void drawPath(Path path, Paint paint) => paths++;
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    await loadMaterialIconsFont();
  });

  testWidgets('the active pill is the brand neon for every rank (not the rank colour)', (t) async {
    for (final level in [1, 3, 12]) {
      await pumpV2(t, _bar(1, rank: RankTokens.forLevel(level)), reducedMotion: true);
      expect(_pill(t).gradient, kV2NavPillGradient, reason: 'level $level');
      expect(_pill(t).boxShadow, v2NavPillHalo(0), reason: 'resting halo, level $level');
    }
  });

  testWidgets('breathing halo: runs with motion on, ends by itself; none under reduced motion', (t) async {
    await pumpV2(t, _bar(0), reducedMotion: true);
    await pumpV2(t, _bar(2), reducedMotion: true);
    await t.pump();
    expect(t.hasRunningAnimations, isFalse, reason: 'reduced motion: no stretch, pop or breathing');

    await pumpV2(t, _bar(0));
    await t.pump(const Duration(seconds: 10));
    await pumpV2(t, _bar(2));
    await t.pump(const Duration(milliseconds: 1500));
    expect(t.hasRunningAnimations, isTrue, reason: 'the halo breathes after the pill lands');
    await t.pump(V2NavPill.breath * 4);
    expect(t.hasRunningAnimations, isFalse, reason: 'bounded: no endless ticker on the bar');
  });

  testWidgets('the pill has its own layer (the breathing repaints only the pill)', (t) async {
    await pumpV2(t, _bar(3), reducedMotion: true);
    expect(
      find.ancestor(of: find.byType(V2NavPill), matching: find.byType(RepaintBoundary)).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('Profil active: the rank ring sits on a night disc (green ranks stay visible)', (t) async {
    final shot = GlobalKey();
    for (final level in [3, 4]) {
      await pumpV2(t, _bar(4, rank: RankTokens.forLevel(level), badge: 12),
          reducedMotion: true, dpr: 4, boundaryKey: shot);
      final disc = t.widget<Container>(find.byKey(kV2NavRankBacking));
      expect((disc.decoration as BoxDecoration).color, MgColors.night);
      expect(t.getSize(find.byKey(kV2NavRankBacking)), const Size(38, 38));
      await maybeShot(t, shot, 'nav_profil_active_l${level}__cs__360');
    }
    await pumpV2(t, _bar(0), reducedMotion: true);
    expect(find.byKey(kV2NavRankBacking), findsNothing, reason: 'inactive: the ring as before');
    expect(t.takeException(), isNull);
  });

  test('pill width and the active label step-down', () {
    // End pills keep 6 px from the bar edge.
    expect(V2NavBar.pillWidth([30, 40, 40, 40, 30], 0, 64), lessThanOrEqualTo(64 - 12));
    expect(V2NavBar.pillWidth([30, 40, 40, 40, 30], 4, 64), lessThanOrEqualTo(64 - 12));
    // A label that fits keeps its size; a tight one steps down, at most 12 %.
    expect(V2NavBar.activePx(50, 76, 11), 11);
    expect(V2NavBar.activePx(80, 84, 11), moreOrLessEquals(11 * 72 / 80));
    expect(V2NavBar.activePx(120, 84, 11), moreOrLessEquals(11 * V2NavBar.minActiveScale));
  });

  test('motorcycle names paint the font glyph, other names their paths', () {
    expect(kMgGlyphIcons.keys, containsAll([MgIcons.moto, MgIcons.bike]));
    for (final n in [MgIcons.moto, MgIcons.bike]) {
      final c = _CountCanvas();
      MgIconPainter(n, MgColors.ink).paint(c, const Size(24, 24));
      expect(c.paths, 0, reason: '$n: no stick paths');
      expect(c.paragraphs, 1, reason: '$n: one glyph');
    }
    final c = _CountCanvas();
    MgIconPainter(MgIcons.home, MgColors.ink).paint(c, const Size(24, 24));
    expect(c.paths, greaterThan(0));
    expect(c.paragraphs, 0);
  });
}
