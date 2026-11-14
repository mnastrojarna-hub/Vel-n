// Hide-on-scroll review fixes (owner 2026-11-08): with the bars SHOWN a
// settled bike's caption (price + Detail) rides above the nav (Domů: also
// above the scroll-to-top button); a snap's spring back / an overshoot's
// return is physics and never unfolds the bars; a bottom sheet on the shell
// navigator never folds the nav behind it; a page pushed on the shell
// navigator (also a pageless `Navigator.push`) brings the bars back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_chrome_lift.dart';
import 'package:motogo_app/core/v2/chrome/mg_hide_on_scroll.dart';
import 'package:motogo_app/core/v2/chrome/mg_nav_band.dart';
import 'package:motogo_app/core/v2/chrome/mg_to_top.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

ScrollPosition _pos(WidgetTester t, Type screen) =>
    t.state<ScrollableState>(find.descendant(of: find.byType(screen), matching: find.byType(Scrollable)).first).position;

MgSnapZone _zone(WidgetTester t) =>
    t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;

List<String> _ids(WidgetTester t) => t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false)).ids;

/// The caption block (tags … price + CTA) of card [key] and its CTA.
Rect _caption(WidgetTester t, Key key) => t.getRect(find
    .descendant(of: find.descendant(of: find.byKey(key), matching: find.byType(MgChromeLift)), matching: find.byType(Padding))
    .first);
Rect _cta(WidgetTester t, Key key) => t.getRect(find.descendant(of: find.byKey(key), matching: find.byType(MgCta)));

double _navTop(WidgetTester t) => t.getRect(find.byType(MgNavBand)).top;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

/// Every value the bars take after this call.
List<bool> _log(WidgetTester t, Finder inShell) {
  final c = MgBarsScope.read(t.element(inShell))!;
  final log = <bool>[];
  void l() => log.add(c.hidden);
  c.addListener(l);
  addTearDown(() => c.removeListener(l));
  return log;
}

final _search = <String, Widget Function(GoRouterState)>{'/search': (_) => const MotorkyScreenV2()};

final _sheetCtrl = ScrollController();
Widget _page(GoRouterState _) => Builder(
      builder: (context) => ListView.builder(
        key: const ValueKey('page'),
        itemCount: 120,
        itemBuilder: (_, i) => i == 0
            ? TextButton(
                key: const ValueKey('open-sheet'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => ListView.builder(
                    key: const ValueKey('sheet-list'),
                    controller: _sheetCtrl,
                    itemCount: 80,
                    itemBuilder: (_, i) => SizedBox(height: 60, child: Text('sheet $i')),
                  ),
                ),
                child: const Text('open'),
              )
            : SizedBox(height: 80, child: Text('row $i')),
      ),
    );

void main() {
  setUpAll(loadMontserrat);

  testWidgets('Motorky: settled on a bike with the bars SHOWN, the caption (price + Detail) sits above the nav', (t) async {
    await pumpBarsShell(t, '/search', _search);
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final ids = _ids(t);
    final pos = _pos(t, MotorkyScreenV2);
    pos.jumpTo(z.offsetOf(1));
    await _settle(t);
    final key = ValueKey('mc-${ids[1]}');
    expect(navFolded(t), isFalse);
    expect(_navTop(t), 844 - 34 - 64);
    expect(_cta(t, key).bottom, lessThanOrEqualTo(_navTop(t)), reason: 'Detail fully above the tab row');
    // v5.0.1: past the first bike the "back to the top" arrow shows → the
    // caption also rides above its slot.
    expect(_caption(t, key).bottom, moreOrLessEquals(_navTop(t) - kMgToTopSlot, epsilon: 0.5));
    final arrow = t.getRect(find.byKey(const ValueKey('mg-to-top')));
    expect(arrow.bottom, lessThanOrEqualTo(_navTop(t)));
    expect(_caption(t, key).bottom, lessThanOrEqualTo(arrow.top + 0.5), reason: 'never under the arrow');
    // Folded (a user drag onto bike 2): the caption rides down to the card's foot.
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.65));
    await _settle(t);
    expect(navFolded(t), isTrue);
    expect(pos.pixels, moreOrLessEquals(z.offsetOf(2), epsilon: 1));
    final k2 = ValueKey('mc-${ids[2]}');
    expect(_caption(t, k2).bottom, moreOrLessEquals(844 - 34, epsilon: 0.5));
    expect(t.getSize(find.byKey(k2)).height, 844 - 34, reason: 'the lift never changes the card height');
    // Any scroll up: the nav is back and the caption with it.
    await slowDrag(t, find.byType(CustomScrollView), 60);
    await _settle(t);
    expect(navFolded(t), isFalse);
    final k = find.byKey(k2).evaluate().isNotEmpty ? k2 : key;
    expect(_cta(t, k).bottom, lessThanOrEqualTo(_navTop(t) + 0.5));
    await _drain(t);
  });

  testWidgets('Domů: with the bars and the scroll-to-top button shown, the caption rides above both', (t) async {
    final routes = <String, Widget Function(GoRouterState)>{'/': (_) => const HomeScreenV2()};
    await pumpBarsShell(t, '/', routes, overrides: homeCases()['s0']!());
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final ids = _ids(t);
    _pos(t, HomeScreenV2).jumpTo(z.offsetOf(1));
    await _settle(t);
    final key = ValueKey('home-mc-${ids[1]}');
    final toTop = t.getRect(find.byKey(const ValueKey('mg-to-top')));
    expect(navFolded(t), isFalse);
    expect(toTop.bottom, lessThanOrEqualTo(_navTop(t)));
    expect(_caption(t, key).bottom, lessThanOrEqualTo(toTop.top + 0.5), reason: 'never under the to-top button');
    expect(_cta(t, key).bottom, lessThanOrEqualTo(toTop.top));
    await _drain(t);
  });

  testWidgets('snap: an aborted swipe springs back to its bike with the bars kept folded', (t) async {
    await pumpBarsShell(t, '/search', _search);
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final pos = _pos(t, MotorkyScreenV2);
    pos.jumpTo(z.offsetOf(1));
    await _settle(t);
    final log = _log(t, find.byType(MotorkyScreenV2));
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.3));
    await _settle(t);
    expect(pos.pixels, moreOrLessEquals(z.offsetOf(1), epsilon: 1), reason: 'back to the same bike');
    expect(navFolded(t), isTrue);
    expect(log, [true], reason: 'folded by the finger, never unfolded by the spring');
    // A 60 px peek and release: the same.
    await slowDrag(t, find.byType(CustomScrollView), -60);
    await _settle(t);
    expect(pos.pixels, moreOrLessEquals(z.offsetOf(1), epsilon: 1));
    expect(log, [true]);
    await _drain(t);
  });

  testWidgets('snap: a fling down on the last bike never overshoots / toggles the bars (iOS physics)', (t) async {
    await pumpBarsShell(t, '/search', _search);
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    final pos = _pos(t, MotorkyScreenV2);
    // Onto the last bike by a user drag (bars folded, the folded geometry).
    pos.jumpTo(z.offsetOf(z.count - 2));
    await _settle(t);
    await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.65));
    await _settle(t);
    final last = z.offsetOf(z.count - 1);
    expect(pos.pixels, moreOrLessEquals(last, epsilon: 1));
    expect(navFolded(t), isTrue);
    final log = _log(t, find.byType(MotorkyScreenV2));
    for (var i = 0; i < 2; i++) {
      // A short flick (in range: the last bike ends 32 px before the end).
      await t.fling(find.byType(CustomScrollView), const Offset(0, -40), 6000);
      var max = pos.pixels;
      for (var f = 0; f < 30; f++) {
        await t.pump(const Duration(milliseconds: 40));
        if (pos.pixels > max) max = pos.pixels;
      }
      expect(max, lessThanOrEqualTo(last + 40), reason: 'the spring never runs past where the finger left');
      expect(pos.pixels, moreOrLessEquals(last, epsilon: 1), reason: 'back on the last bike');
    }
    expect(log, isEmpty, reason: 'no hide → show flicker');
    expect(navFolded(t), isTrue);
    await _drain(t);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a bottom sheet on the shell navigator never folds the nav; the page below still does', (t) async {
    await pumpBarsShell(t, '/long', {'/long': _page});
    await t.tap(find.byKey(const ValueKey('open-sheet')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    final top = t.getRect(find.byKey(const ValueKey('sheet-list'))).top;
    await t.drag(find.byKey(const ValueKey('sheet-list')), const Offset(0, -200));
    await settleChrome(t);
    expect(_sheetCtrl.offset, greaterThan(100), reason: 'the sheet list did scroll');
    expect(navFolded(t), isFalse, reason: 'sheet scrolling is not the page');
    expect(t.getRect(find.byKey(const ValueKey('sheet-list'))).top, top, reason: 'the sheet never moves under the finger');
    Navigator.of(t.element(find.byKey(const ValueKey('sheet-list')))).pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.drag(find.byKey(const ValueKey('page')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue, reason: 'the page scroll folds again once the sheet is gone');
    // A sheet opened while folded leaves the bars as they are.
    final c = MgBarsScope.read(t.element(find.byKey(const ValueKey('page'))))!;
    expect(c.popupOnTop, isFalse);
  });

  testWidgets('a page pushed on the shell navigator (Navigator.push, no router location) brings the bars back', (t) async {
    await pumpBarsShell(t, '/long', {'/long': _page});
    await t.drag(find.byKey(const ValueKey('page')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    final nav = Navigator.of(t.element(find.byKey(const ValueKey('page'))));
    nav.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(key: ValueKey('map'), color: Color(0xFF223344))));
    await t.pump();
    await settleChrome(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('map')), findsOneWidget);
    expect(navFolded(t), isFalse, reason: 'a non-scrolling page could never unfold it');
    // Back to the list: still shown; a drag there folds again.
    nav.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(navFolded(t), isFalse);
    await t.drag(find.byKey(const ValueKey('page')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
  });
}
