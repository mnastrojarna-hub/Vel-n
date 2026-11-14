// One item per swipe (owner v5.0.1: "vždycky chci listovat pouze o jednu
// … nikdy ne o celý … rychlým dvojitým tahem"): however fast the fling or
// long the drag, a release settles on the NEIGHBOUR of the item the drag
// started on; a quick second swipe moves one more; the header above the
// first item still rests freely; the full-width pagers (detail, funnel)
// move one page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/gestures/mg_one_step.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

const _itemH = 600.0;
const _headerH = 300.0;

/// MgPage: a 300 px header, then 12 snapped items of 600 px.
Widget _page(MgSnapZone zone) => MgPage(
      header: const SizedBox(height: _headerH, child: ColoredBox(color: Colors.black12)),
      overlapHero: false,
      snap: zone,
      slivers: [
        MgSnapZoneSliver(
          zone: zone,
          extent: _itemH,
          count: 12,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => SizedBox(height: _itemH, child: Center(child: Text('ITEM $i'))),
              childCount: 12,
            ),
          ),
        ),
      ],
    );

ScrollPosition _pos(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Item index the page rests on (fraction = between two).
double _at(WidgetTester t, MgSnapZone z) => (_pos(t).pixels - z.start) / z.extent;

/// A drag of [dy] in a few quick moves, released while still moving fast.
Future<void> _longFling(WidgetTester t, double dy) async {
  final g = await t.startGesture(const Offset(180, 600));
  for (var i = 0; i < 8; i++) {
    await g.moveBy(Offset(0, dy / 8));
    await t.pump(const Duration(milliseconds: 8));
  }
  await g.up();
  await t.pump();
}

void main() {
  setUpAll(loadMontserrat);

  test('anchor: origin = drag start, or the interrupted snap target; none at rest', () {
    final a = MgSwipeAnchor();
    expect(a.origin(600), isNull);
    a.dragStart(1500);
    expect(a.origin(600), 1500);
    a.aimed(1800);
    expect(a.origin(600), 1500, reason: 'fixed for the whole swipe (a re-run snap keeps it)');
    a.settled();
    a.dragStart(1500);
    expect(a.origin(600), 1800, reason: 'second quick swipe counts from the target');
    a.dragStart(1200);
    expect(a.origin(600), 1200, reason: 'a whole item away: not the same swipe');
    a.settled();
    expect(a.origin(600), isNull);
    expect(mgSwipeOriginIndex(0, 300, 600), -1);
    expect(mgSwipeOriginIndex(300, 300, 600), 0);
    expect(mgSwipeOriginIndex(1150, 300, 600), 1);
    expect(mgSnapVelocity(0, 600, 20000), 18 * 600);
    expect(mgSnapVelocity(0, 600, -900), 0, reason: 'never against the target');
    expect(MgOnePagePhysics.targetPage(400, 400, 30000, 50, 0), 1);
    expect(MgOnePagePhysics.targetPage(700, 400, 30000, 50, 0), 1, reason: 'clamped to the neighbour');
    expect(MgOnePagePhysics.targetPage(700, 400, 30000, 50, null), 2);
  });

  testWidgets('a very fast fling moves exactly one item, both directions', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    _pos(t).jumpTo(z.offsetOf(3));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -300), 30000);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(4, epsilon: 0.01));
    await t.fling(find.byType(CustomScrollView), const Offset(0, 300), 30000);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(3, epsilon: 0.01));
  });

  testWidgets('a long drag (1.7 items) released fast still ends on the next item', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    _pos(t).jumpTo(z.offsetOf(2));
    await t.pump();
    await _longFling(t, -_itemH * 1.7);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(3, epsilon: 0.01));
  });

  testWidgets('the snap never overshoots past the next item and comes back', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    _pos(t).jumpTo(z.offsetOf(1));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -200), 25000);
    var max = 0.0;
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (_at(t, z) > max) max = _at(t, z);
    }
    await _settle(t);
    expect(max, lessThanOrEqualTo(2.001));
    expect(_at(t, z), moreOrLessEquals(2, epsilon: 0.01));
  });

  testWidgets('a quick second swipe during the snap moves one more (not two)', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    _pos(t).jumpTo(z.offsetOf(1));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -200), 8000);
    await t.pump(const Duration(milliseconds: 60));
    expect(_at(t, z), lessThan(2));
    await t.fling(find.byType(CustomScrollView), const Offset(0, -200), 8000);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(3, epsilon: 0.01));
  });

  testWidgets('header: free resting; a fling up from item 3 lands on item 2, not in the header', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    await slowDrag(t, find.byType(CustomScrollView), -100);
    await _settle(t);
    expect(_pos(t).pixels, moreOrLessEquals(100, epsilon: 2));
    await t.fling(find.byType(CustomScrollView), const Offset(0, -150), 30000);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(0, epsilon: 0.01), reason: 'from the header: the first item');
    _pos(t).jumpTo(z.offsetOf(3));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, 300), 30000);
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(2, epsilon: 0.01));
    // From the first item a flick up still leaves into the header.
    _pos(t).jumpTo(z.offsetOf(0));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, 300), 3000);
    await _settle(t);
    expect(_pos(t).pixels, lessThan(z.start));
  });

  testWidgets('a programmatic jump after a swipe is never pulled back', (t) async {
    final z = MgSnapZone();
    await pumpV2(t, _page(z));
    _pos(t).jumpTo(z.offsetOf(1));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -200), 8000);
    await _settle(t);
    _pos(t).jumpTo(z.offsetOf(8));
    await _settle(t);
    expect(_at(t, z), moreOrLessEquals(8, epsilon: 0.01));
  });

  testWidgets('full-width pager: one page per swipe however fast', (t) async {
    final anchor = MgSwipeAnchor();
    final pc = PageController();
    addTearDown(pc.dispose);
    await pumpV2(
      t,
      MgSwipeAnchorListener(
        anchor: anchor,
        axis: Axis.horizontal,
        child: PageView.builder(
          controller: pc,
          pageSnapping: false,
          physics: MgOnePagePhysics(anchor: anchor),
          itemCount: 10,
          itemBuilder: (_, i) => Center(child: Text('PAGE $i')),
        ),
      ),
    );
    await t.fling(find.byType(PageView), const Offset(-200, 0), 30000);
    await _settle(t);
    expect(pc.page, moreOrLessEquals(1, epsilon: 0.01));
    final g = await t.startGesture(const Offset(340, 300));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(-110, 0));
      await t.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await _settle(t);
    expect(pc.page, moreOrLessEquals(2, epsilon: 0.01), reason: 'a 1.8-page drag still moves one page');
  });

  testWidgets('Motorky (real screen): a very fast fling from bike 1 rests on bike 2', (t) async {
    await pumpBarsShell(t, '/search', <String, Widget Function(GoRouterState)>{
      '/search': (_) => const MotorkyScreenV2(),
      '/moto/:id': (s) => MotoDetailScreen(motoId: s.pathParameters['id']!),
    });
    await t.pump(const Duration(milliseconds: 500));
    final z = t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;
    expect(z.count, greaterThanOrEqualTo(3));
    final pos = t
        .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
        .position;
    pos.jumpTo(z.offsetOf(0));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -250), 30000);
    await _settle(t);
    expect((pos.pixels - z.start) / z.extent, moreOrLessEquals(1, epsilon: 0.01));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
