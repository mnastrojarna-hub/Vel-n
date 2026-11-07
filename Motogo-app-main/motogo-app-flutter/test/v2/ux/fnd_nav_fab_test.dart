// FND-16 nav motion + AI button lift / coach, FND-17 loops pause off-screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_coach.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/chrome/mg_top_banner.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/motion/mg_anim_loops.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

const _coach = 'Zeptej se kdykoli. Jsme tu pro tebe.';

void main() {
  setUpAll(loadMontserrat);
  setUp(MgAiCoach.debugReset);

  group('AI button placement', () {
    const slot = Rect.fromLTWH(288, 600, 56, 56);
    test('free → rest; blocked with room above → lift', () {
      expect(mgFabPlacementFor(slot, const []), (MgFabState.rest, 0.0));
      final (s, lift) = mgFabPlacementFor(slot, const [(Rect.fromLTWH(16, 640, 328, 48), MgAvoidKind.cta)]);
      expect(s, MgFabState.lift);
      expect(lift, closeTo(656 - (640 - 12), 0.01));
    });
    test('no room above (lift > 56 or blocked) → off for cta, peek for tap', () {
      const tall = Rect.fromLTWH(16, 560, 328, 120);
      expect(mgFabPlacementFor(slot, const [(tall, MgAvoidKind.cta)]).$1, MgFabState.off);
      expect(mgFabPlacementFor(slot, const [(tall, MgAvoidKind.tap)]).$1, MgFabState.peek);
      expect(mgFabPlacementFor(slot, const [(tall, MgAvoidKind.keep)]).$1, MgFabState.peek);
      final blocked = mgFabPlacementFor(slot, const [
        (Rect.fromLTWH(16, 640, 328, 48), MgAvoidKind.cta),
        (Rect.fromLTWH(16, 560, 328, 40), MgAvoidKind.keep),
      ]);
      expect(blocked.$1, MgFabState.off);
      expect(mgFabStateFor(slot, const [(tall, MgAvoidKind.keep)]), MgFabState.peek);
    });
  });

  testWidgets('coach: shown once, ✕ hides it for good (also after a restart)', (tester) async {
    await pumpShellV2(tester, '/');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_coach), findsOneWidget);
    final close = find.descendant(of: find.byType(MgAiCoachBubble), matching: find.bySemanticsLabel('Zavřít'));
    await tester.tap(close.evaluate().isEmpty ? find.text(_coach) : close);
    await tester.pump();
    expect(find.text(_coach), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool(MgAiCoach.prefKey), isTrue);
    MgAiCoach.debugReset();
    await pumpShellV2(tester, '/', prefs: const {MgAiCoach.prefKey: true});
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_coach), findsNothing);
  });

  testWidgets('coach never on routes where the AI button is hidden', (tester) async {
    await pumpShellV2(tester, '/sos');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_coach), findsNothing);
  });

  testWidgets('nav: label colour animates, re-tap nudges the icon up', (tester) async {
    await pumpShellV2(tester, '/search', prefs: const {MgAiCoach.prefKey: true});
    expect(find.descendant(of: find.byType(V2NavBar), matching: find.byType(AnimatedDefaultTextStyle)), findsNWidgets(5));
    await tester.tap(find.text('Motorky'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final ys = tester
        .widgetList<Transform>(find.descendant(of: find.byType(V2NavBar), matching: find.byType(Transform)))
        .map((t) => t.transform.getTranslation().y)
        .where((y) => y < -1);
    expect(ys, isNotEmpty);
    await tester.pumpAndSettle();
  });

  group('loops pause off-screen', () {
    Widget list(ScrollController c, Widget loop) => ListView(controller: c, children: [
          loop,
          for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('row $i')),
        ]);

    testWidgets('CTA loop: scrolled out → no ticker, back → running', (tester) async {
      final c = ScrollController();
      await pumpV2(tester, list(c, Padding(padding: const EdgeInsets.all(16), child: MgCta(label: 'Rezervovat', onTap: () {}, loop: true))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      c.jumpTo(1200);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);
      c.jumpTo(0);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('marquee: own repaint boundary, pauses off-screen', (tester) async {
      final c = ScrollController();
      final long = 'Sezóna 2027 začíná — rezervuj si motorku včas, nejlepší termíny mizí jako první ' * 2;
      await pumpV2(tester, list(c, ColoredBox(color: Colors.black, child: MgTopBanner(text: long))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.descendant(of: find.byType(MgTopBanner), matching: find.byType(RepaintBoundary)), findsWidgets);
      expect(find.descendant(of: find.byType(MgTopBanner), matching: find.byType(MgLoopClock)), findsOneWidget);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      c.jumpTo(1500);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
