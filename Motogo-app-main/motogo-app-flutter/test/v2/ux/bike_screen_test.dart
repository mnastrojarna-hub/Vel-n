// One bike per screen + the detail pager (owner 2026-11-08 "vždycky
// motorka je na celou stránku … swipovat doprava i doleva … zpět"): the
// Motorky / Domů cards fill the folded viewport, a release settles on one
// bike (not under reduced motion, not in the header), the detail pager
// swipes through the shown list with ‹ n / m ›, its controls fold while the
// bike is scrolled, and going back lands on the bike seen last.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_hide_on_scroll.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/motion/mg_sticky_slide.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_pager_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

final _routes = <String, Widget Function(GoRouterState)>{
  '/search': (_) => const MotorkyScreenV2(),
  '/moto/:id': (s) => MotoDetailScreen(motoId: s.pathParameters['id']!),
};

ScrollPosition _page(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
    .position;

MgSnapZone _zone(WidgetTester t) => t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver)).zone;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(loadMontserrat);

  testWidgets('Motorky: every card is the folded viewport tall (844 − 34 band), one bike per screen', (t) async {
    await pumpBarsShell(t, '/search', _routes);
    await t.pump(const Duration(milliseconds: 500));
    final cards = find.byType(MotoCardFullV2);
    expect(cards, findsWidgets);
    expect(t.getSize(cards.first).height, 844 - 34);
    final z = _zone(t);
    expect(z.active, isTrue);
    expect(z.extent, 844 - 34 + kBikeScreenGap);
    // Snapped on bike 2 with the bars folded: the card IS the screen.
    _page(t).jumpTo(z.offsetOf(1));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await _settle(t);
    expect(navFolded(t), isTrue);
    final r = t.getRect(cards.at(1));
    expect(r.top, moreOrLessEquals(0, epsilon: 0.5));
    expect(r.bottom, moreOrLessEquals(844 - 34, epsilon: 0.5));
    // Top controls under the status bar inset (47), never under the clock.
    expect(t.widget<MotoCardFullV2>(cards.at(1)).topInset, 47);
    await _drain(t);
  });

  testWidgets('snap: a slow release settles on the nearer bike, a flick moves at least one bike', (t) async {
    await pumpBarsShell(t, '/search', _routes);
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final pos = _page(t);
    pos.jumpTo(z.offsetOf(1));
    await t.pump();
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.3 + 18));
    await _settle(t);
    expect(pos.pixels, moreOrLessEquals(z.offsetOf(1), epsilon: 1), reason: '30 % → back to the same bike');
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.65 + 18));
    await _settle(t);
    expect(pos.pixels, moreOrLessEquals(z.offsetOf(2), epsilon: 1), reason: '65 % → the next bike');
    pos.jumpTo(z.offsetOf(0));
    await t.pump();
    await t.fling(find.byType(CustomScrollView), const Offset(0, -120), 1200);
    await _settle(t);
    final k = (pos.pixels - z.start) / z.extent;
    expect(k, greaterThanOrEqualTo(1));
    expect((k - k.round()).abs(), lessThan(0.01), reason: 'a fling ends on a bike, never between two');
    await _drain(t);
  });

  testWidgets('snap stays out of the header and under reduced motion', (t) async {
    await pumpBarsShell(t, '/search', _routes);
    await t.pump(const Duration(milliseconds: 500));
    final pos = _page(t);
    await slowDrag(t, find.byType(CustomScrollView), -118);
    await _settle(t);
    expect(pos.pixels, moreOrLessEquals(100, epsilon: 2), reason: 'dates / filters: free resting');
    await _drain(t);

    await pumpBarsShell(t, '/search', _routes, reducedMotion: true);
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    expect(z.active, isFalse);
    final p2 = _page(t);
    p2.jumpTo(z.offsetOf(1));
    await t.pump();
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.3 + 18));
    await _settle(t);
    expect(p2.pixels, moreOrLessEquals(z.offsetOf(1) + z.extent * 0.3, epsilon: 2), reason: 'no animated snap');
    await _drain(t);
  });

  testWidgets('detail: swipe ‹ › through the shown list, controls fold on scroll, back lands on the last bike', (t) async {
    final router = await pumpBarsShell(t, '/search', _routes, size: const Size(412, 915));
    await t.pump(const Duration(milliseconds: 500));
    final ids = t.widget<BikeScreenList>(find.byType(BikeScreenList)).ids;
    expect(ids.length, greaterThanOrEqualTo(3));
    final z = _zone(t);
    // Open bike 1 from its card.
    _page(t).jumpTo(z.offsetOf(1));
    await t.pump();
    await t.tap(find.byType(MotoCardFullV2).at(1), warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(MotoDetailPagerV2View), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(MotoDetailPagerV2View)));
    expect(c.read(filteredMotoIdsProvider), ids, reason: 'the pager swipes through the shown list');
    expect(find.text('2 / ${ids.length}'), findsOneWidget);
    expect(c.read(catalogShownMotoProvider), ids[1]);
    // Scrolling the bike down folds the pager controls + the nav.
    MgStickySlide back() => t.widget<MgStickySlide>(
        find.ancestor(of: find.byWidgetPredicate((w) => w is MgV2Back && w.style == MgBackStyle.photo), matching: find.byType(MgStickySlide)).first);
    final detailScroll = find.descendant(of: find.byType(MotoDetailPagerV2View), matching: find.byType(CustomScrollView)).first;
    await t.drag(detailScroll, const Offset(0, -400));
    await settleChrome(t);
    expect(back().visible, isFalse);
    expect(navFolded(t), isTrue);
    // Swipe to the next bike: controls back, counter + shown bike follow.
    await t.drag(find.byType(PageView).first, const Offset(-350, 0));
    await _settle(t);
    expect(find.text('3 / ${ids.length}'), findsOneWidget);
    expect(back().visible, isTrue);
    expect(navFolded(t), isFalse);
    expect(c.read(catalogShownMotoProvider), ids[2]);
    // Back: the list shows bike 3 at the top (not the top of the list, not bike 2).
    router.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(MotoDetailPagerV2View), findsNothing);
    expect(_page(t).pixels, moreOrLessEquals(_zone(t).offsetOf(2), epsilon: 1));
    await _drain(t);
  });

  testWidgets('bars controller: hidden reads false while the screen reader is on', (t) async {
    final c = MgBarsController();
    addTearDown(c.dispose);
    expect(c.hidden, isFalse);
    c.enabled = false;
    expect(c.hidden, isFalse);
    c.enabled = true;
    c.show();
    expect(c.hidden, isFalse);
  });
}
