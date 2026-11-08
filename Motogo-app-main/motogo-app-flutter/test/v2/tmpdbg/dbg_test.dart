import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import '../screens/home_test.dart' show homeCases;
import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(loadMontserrat);
  testWidgets('dbg', (t) async {
    await pumpBarsShell(t, '/', <String, Widget Function(GoRouterState)>{'/': (_) => const HomeScreenV2()}, overrides: homeCases()['s0']!(), reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    final zone = t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;
    final pos = t.state<ScrollableState>(find.descendant(of: find.byType(HomeScreenV2), matching: find.byType(Scrollable)).first).position;
    pos.jumpTo(zone.offsetOf(0) - 120);
    await t.pump();
    await slowDrag(t, find.byType(CustomScrollView), -120);
    for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 100)); }
    print('folded ${navFolded(t)} pixels ${pos.pixels} target ${zone.offsetOf(0)}');
    final disc = find.descendant(of: find.byType(MgAiFab), matching: find.byType(MgAiDisc));
    print('fab ${t.getRect(disc)}');
    for (final e in find.byType(MgFabAvoid).evaluate()) {
      final ro = e.renderObject as RenderBox;
      print('avoid ${(e.widget as MgFabAvoid).kind} ${ro.localToGlobal(Offset.zero) & ro.size}');
    }
    final op = t.widgetList<AnimatedOpacity>(find.descendant(of: find.byType(MgAiFab), matching: find.byType(AnimatedOpacity))).map((w) => w.opacity).toList();
    print('opacities $op');
  });
}
