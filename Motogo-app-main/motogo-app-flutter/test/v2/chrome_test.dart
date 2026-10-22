// v2 chrome: AI button placement vs MgFabAvoid zones (rest / peek / off),
// dock height reporting, page padding, app bar title fallback, photo hero,
// status strips, rank frame / hero across tiers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_app_bar.dart';
import 'package:motogo_app/core/v2/chrome/mg_chrome_metrics.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/chrome/mg_photo_hero.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/rank/rank_frame.dart';
import 'package:motogo_app/core/v2/rank/rank_hero.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';

import 'support/v2_harness.dart';

/// Minimal shell: content + floating AI button bottom-right 16 / 12.
Widget _shell(MgShellChrome chrome, Widget content) => MgChromeScope(
      chrome: chrome,
      navVisible: true,
      fabVisible: true,
      child: Stack(children: [
        Positioned.fill(child: content),
        const Positioned(right: 16, bottom: 12, child: MgAiFab()),
      ]),
    );

/// A control of [kind] at the bottom-right corner (under the AI button) or
/// at the top-left.
Widget _zone(MgAvoidKind kind, {bool underFab = true}) => Align(
      alignment: underFab ? Alignment.bottomRight : Alignment.topLeft,
      child: MgFabAvoid(kind: kind, child: const SizedBox(width: 120, height: 60)),
    );

double _fabOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.descendant(of: find.byType(MgAiFab), matching: find.byType(AnimatedOpacity))).opacity;

void main() {
  setUpAll(loadMontserrat);

  group('AI button placement', () {
    test('pure rule', () {
      const slot = Rect.fromLTWH(288, 700, 56, 56);
      expect(mgFabStateFor(slot, const []), MgFabState.rest);
      expect(mgFabStateFor(slot, const [(Rect.fromLTWH(0, 0, 100, 40), MgAvoidKind.cta)]), MgFabState.rest);
      expect(mgFabStateFor(slot, const [(Rect.fromLTWH(250, 690, 100, 40), MgAvoidKind.tap)]), MgFabState.peek);
      expect(mgFabStateFor(slot, const [
        (Rect.fromLTWH(250, 690, 100, 40), MgAvoidKind.tap),
        (Rect.fromLTWH(0, 740, 360, 56), MgAvoidKind.cta),
      ]), MgFabState.off);
      // inflated by 8: a CTA 6 px away still counts
      expect(mgFabStateFor(slot, const [(Rect.fromLTWH(0, 762, 360, 50), MgAvoidKind.sos)]), MgFabState.off);
    });

    for (final c in [
      (MgAvoidKind.cta, true, 0.0),
      (MgAvoidKind.sos, true, 0.0),
      (MgAvoidKind.tap, true, 0.85),
      (MgAvoidKind.cta, false, 1.0),
    ]) {
      testWidgets('zone ${c.$1} underFab=${c.$2} → opacity ${c.$3}', (tester) async {
        final chrome = MgShellChrome();
        addTearDown(chrome.dispose);
        await pumpV2(tester, _shell(chrome, _zone(c.$1, underFab: c.$2)), reducedMotion: true);
        await tester.pump();
        await tester.pump();
        expect(_fabOpacity(tester), c.$3);
        if (c.$3 == 0) {
          // off = no hit, no semantics
          expect(tester.widget<IgnorePointer>(find.descendant(of: find.byType(MgAiFab), matching: find.byType(IgnorePointer)).first).ignoring, isTrue);
        }
      });
    }

    testWidgets('hidden route → off; tap pushes nothing without a router (no crash)', (tester) async {
      final chrome = MgShellChrome();
      addTearDown(chrome.dispose);
      await pumpV2(tester, MgChromeScope(
        chrome: chrome,
        navVisible: false,
        fabVisible: false,
        child: const Stack(children: [Positioned(right: 16, bottom: 12, child: MgAiFab(hidden: true))]),
      ), reducedMotion: true);
      await tester.pump();
      expect(_fabOpacity(tester), 0);
    });

    testWidgets('AI disc: label, custom onTap, rank ring on every tier', (tester) async {
      var taps = 0;
      final h = tester.ensureSemantics();
      for (final lvl in [0, 5, 8, 12, 16, 18, 20]) {
        await pumpV2(tester, Center(child: MgAiDisc(onTap: () => taps++)), rank: RankTokens.forLevel(lvl));
        await tester.tap(find.byType(MgAiDisc));
      }
      expect(taps, 7);
      expect(find.bySemanticsLabel('AI Servisní agent'), findsOneWidget);
      h.dispose();
    });
  });

  testWidgets('MgDock reports its height; MgPage pads for strips + FAB', (tester) async {
    final chrome = MgShellChrome();
    addTearDown(chrome.dispose);
    chrome.reportStrips(60);
    await pumpV2(tester, MgChromeScope(
      chrome: chrome,
      navVisible: true,
      fabVisible: true,
      child: Builder(builder: (context) {
        final pad = MgChrome.bottomObstruction(context);
        return MgPage(
          sections: [Text('pad $pad')],
          dock: MgDock(aiDisc: true, contextLine: const Text('pá 23. 10. → ne 25. 10. · 3 dny'),
              child: MgCta(label: 'Rezervovat', price: '10 189 Kč', onTap: () {}, loop: true, size: MgCtaSize.lg60)),
        );
      }),
    ), scaffold: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('pad ${60 + 56 + 12 + 24.0}'), findsOneWidget);
    expect(chrome.dockHeight, greaterThan(60));
    expect(tester.takeException(), isNull);
  });

  for (final lang in kV2Langs) {
    testWidgets('MgAppBar long title + status strips $lang (360)', (tester) async {
      var taps = 0, dismissed = 0;
      await pumpV2(tester, Column(children: [
        MgAppBar(title: 'Nejbližší víkend a další dlouhý titulek obrazovky', subtitle: 'Husqvarna 701 SM', onBack: () {}),
        const Spacer(),
        for (final k in MgStripKind.values)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: MgStatusStrip(
              kind: k,
              title: 'Pokračovat v trase · Okruh Pálavou a Lednicko-valtickým areálem',
              sub: 'Zbývá 14:52',
              onTap: () => taps++,
              onDismiss: k == MgStripKind.verifying ? null : () => dismissed++,
            ),
          ),
      ]), lang: lang);
      await expectCleanFrames(tester);
      await tester.tap(find.byType(MgStatusStrip).first);
      expect(taps, 1);
      expect(find.byType(MgV2Back), findsOneWidget);
    });
  }

  testWidgets('MgPhotoHero renders with the photo-style back', (tester) async {
    var back = 0;
    await pumpV2(tester, MgPhotoHero(
      image: Container(color: Colors.grey),
      title: 'BMW R 1200 GS Adventure',
      meta: 'Mezná · cestovní',
      onBack: () => back++,
      statusPill: const Text('Volná dnes'),
    ), scaffold: false);
    await expectCleanFrames(tester);
    await tester.tap(find.byType(MgV2Back));
    expect(back, 1);
  });

  for (final lvl in [0, 1, 3, 5, 6, 9, 10, 14, 16, 17, 18, 19, 20]) {
    testWidgets('rank frame + hero, level $lvl', (tester) async {
      await pumpV2(tester, Column(children: [
        MgRankHero(
          rank: RankTokens.forLevel(lvl),
          child: Row(children: [
            RankFrame(rank: RankTokens.forLevel(lvl), arcPct: 50, child: const ColoredBox(color: Colors.black)),
            const SizedBox(width: 24),
            RankFrame(rank: RankTokens.forLevel(lvl), size: 30, circle: true, ringWidth: 2.5, arcPct: 75, arcGap: 5, showLevel: false, child: const ColoredBox(color: Colors.black)),
          ]),
        ),
      ]), scaffold: false);
      await expectCleanFrames(tester);
    });
  }
}
