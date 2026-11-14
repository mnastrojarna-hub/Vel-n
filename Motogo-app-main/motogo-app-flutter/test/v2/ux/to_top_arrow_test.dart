// "Back to the top" arrow (owner v5.0.1: "ta šipka, co tam byla v pravém
// dolním rohu"): Motorky (and Domů, same MgPage piece) — hidden on the
// first bike, shown once it is left, bottom-right next to the AI button
// (never over it, the menu or the strips), labelled, one tap = the top.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_nav_band.dart';
import 'package:motogo_app/core/v2/chrome/mg_to_top.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import '../screens/home_test.dart' show homeCases;

import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

final _search = <String, Widget Function(GoRouterState)>{'/search': (_) => const MotorkyScreenV2()};

ScrollPosition _pos(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
    .position;

MgSnapZone _zone(WidgetTester t) =>
    t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;

double _opacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const ValueKey('mg-to-top')), matching: find.byType(AnimatedOpacity)))
    .opacity;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadMontserrat);

  test('show rule: past the first snapped item, else 600 px', () {
    expect(mgToTopShouldShow(599, null), isFalse);
    expect(mgToTopShouldShow(601, null), isTrue);
    final z = MgSnapZone()
      ..start = 979
      ..extent = 818
      ..count = 5;
    expect(mgToTopShouldShow(700, z), isFalse, reason: 'in the header above the first bike');
    expect(mgToTopShouldShow(979, z), isFalse, reason: 'resting on the first bike');
    expect(mgToTopShouldShow(979 + 818, z), isTrue, reason: 'on the second bike');
    z.count = 0;
    expect(mgToTopShouldShow(700, z), isTrue, reason: 'no list (calculator): 600 px');
  });

  for (final reduced in [false, true]) {
    testWidgets('Motorky: arrow after the first bike, beside the AI button, tap → top (reduced=$reduced)', (t) async {
      await pumpBarsShell(t, '/search', _search, reducedMotion: reduced);
      await t.pump(const Duration(milliseconds: 500));
      final z = _zone(t);
      _pos(t).jumpTo(z.offsetOf(0));
      await _settle(t);
      expect(_opacity(t), 0, reason: 'on the first bike');
      _pos(t).jumpTo(z.offsetOf(2));
      await _settle(t);
      expect(_opacity(t), 1);
      final arrow = t.getRect(find.byKey(const ValueKey('mg-to-top')));
      final navTop = t.getRect(find.byType(MgNavBand)).top;
      // Motorky has no AI button (Domů only): the arrow takes the corner.
      expect(arrow.right, moreOrLessEquals(390 - 16, epsilon: 0.5), reason: '16 px from the edge (the 44 px neon disc)');
      expect(arrow.bottom, lessThanOrEqualTo(navTop - 8));
      expect(find.bySemanticsLabel('Nahoru'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mg-to-top')));
      await t.pump();
      await t.pump(Duration(milliseconds: reduced ? 16 : 400));
      await _settle(t);
      expect(_pos(t).pixels, 0);
      expect(_opacity(t), 0);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('Domů: the arrow sits on the AI button row, left of it, never over it', (t) async {
    await pumpBarsShell(t, '/', {'/': (_) => const HomeScreenV2()}, overrides: homeCases()['s0']!());
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final pos = t
        .state<ScrollableState>(find.descendant(of: find.byType(HomeScreenV2), matching: find.byType(Scrollable)).first)
        .position;
    pos.jumpTo(z.offsetOf(1));
    await _settle(t);
    expect(_opacity(t), 1);
    final arrow = t.getRect(find.byKey(const ValueKey('mg-to-top')));
    final ai = t.getRect(find.byType(MgAiDisc));
    expect(arrow.overlaps(ai), isFalse);
    expect(arrow.right, lessThanOrEqualTo(ai.left - 8));
    expect(arrow.center.dy, moreOrLessEquals(ai.center.dy, epsilon: 1.5), reason: 'on the AI button row');
    expect(arrow.bottom, lessThanOrEqualTo(t.getRect(find.byType(MgNavBand)).top));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
