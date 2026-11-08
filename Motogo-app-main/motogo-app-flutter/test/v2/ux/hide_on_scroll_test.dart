// Hide-on-scroll of the v2 chrome (owner 2026-11-08): scrolling DOWN folds
// the bottom nav (to its safe-area band) and the fixed top parts, scrolling
// UP brings them back; docks / strips / the AI button keep their bottom
// insets; programmatic and horizontal scrolls, screen readers, route
// changes and the top edge keep everything shown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/banner_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/chrome/mg_hide_on_scroll.dart';
import 'package:motogo_app/core/v2/chrome/mg_nav_band.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/chrome/mg_top_banner.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/motion/mg_sticky_slide.dart';

import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

final _ctrl = ScrollController();

Widget _long(GoRouterState _) => ListView.builder(
      key: const ValueKey('long'),
      controller: _ctrl,
      itemCount: 120,
      itemBuilder: (_, i) => SizedBox(height: 80, child: Text('row $i')),
    );

Widget _short(GoRouterState _) => ListView(key: const ValueKey('short'), children: const [Text('one'), Text('two')]);

Widget _pager(GoRouterState _) => ListView(key: const ValueKey('outer'), children: [
      SizedBox(
        height: 300,
        child: PageView(key: const ValueKey('photos'), children: [for (var i = 0; i < 4; i++) Text('photo $i')]),
      ),
      for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('r$i')),
    ]);

Widget _dock(GoRouterState _) => MgPage(
      sections: [for (var i = 0; i < 30; i++) SizedBox(height: 90, child: Text('s$i'))],
      dock: const MgDock(child: SizedBox(key: ValueKey('cta'), height: 48)),
    );

final _routes = <String, Widget Function(GoRouterState)>{
  '/': _long,
  '/long': _long,
  '/routes': _short,
  '/short': _short,
  '/pager': _pager,
  '/dock': _dock,
};

const _h = 844.0, _band = 34.0;

void main() {
  setUpAll(loadMontserrat);

  testWidgets('drag down folds the nav to its band, drag up brings it back; the body grows', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    expect(navFolded(t), isFalse);
    final open = t.getSize(find.byType(MgNavBand)).height;
    expect(open, 64 + _band);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    expect(t.getSize(find.byType(MgNavBand)).height, _band, reason: 'only the safe-area band stays');
    expect(t.getRect(find.byKey(const ValueKey('long'))).bottom, _h - _band, reason: 'the body grows by the tab row');
    expect(t.getRect(find.byType(MgNavBand)).top, _h - _band);
    // The tab row is out of reach (and out of semantics) while folded.
    final ignore = find.ancestor(of: find.byType(V2NavBar), matching: find.byType(IgnorePointer));
    expect(t.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring), isTrue);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, 60));
    await settleChrome(t);
    expect(navFolded(t), isFalse);
    expect(t.getSize(find.byType(MgNavBand)).height, 64 + _band);
  });

  testWidgets('hysteresis: folds after 24 px down, shows after 8 px up — not before', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    _ctrl.jumpTo(400);
    await t.pump();
    final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('long'))));
    // Past the touch slop first, scrolling UP (shown stays shown) — the
    // count of a reversal starts at 0.
    await g.moveBy(const Offset(0, 20));
    await g.moveBy(const Offset(0, 10));
    await t.pump();
    expect(navFolded(t), isFalse);
    var from = _ctrl.offset;
    while (!navFolded(t)) {
      await g.moveBy(const Offset(0, -2));
      await t.pump();
      expect(_ctrl.offset - from, lessThan(30));
    }
    expect(_ctrl.offset - from, inInclusiveRange(MgBarsController.hideAfter - 4, MgBarsController.hideAfter + 2));
    from = _ctrl.offset;
    while (navFolded(t)) {
      await g.moveBy(const Offset(0, 1));
      await t.pump();
      expect(from - _ctrl.offset, lessThan(12));
    }
    expect(from - _ctrl.offset, inInclusiveRange(MgBarsController.showAfter - 1, MgBarsController.showAfter + 1));
    await g.up();
    await settleChrome(t);
  });

  testWidgets('a fling down folds; back at the top = always shown (also after a programmatic scroll-to-top)', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    await t.fling(find.byKey(const ValueKey('long')), const Offset(0, -400), 2000);
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    _ctrl.jumpTo(0);
    await settleChrome(t);
    expect(navFolded(t), isFalse);
  });

  testWidgets('programmatic scrolls never fold', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    _ctrl.jumpTo(1500);
    await settleChrome(t);
    expect(navFolded(t), isFalse);
    _ctrl.animateTo(3000, duration: const Duration(milliseconds: 200), curve: Curves.linear);
    await settleChrome(t);
    expect(_ctrl.offset, 3000);
    expect(navFolded(t), isFalse);
  });

  testWidgets('a horizontal photo pager drag does not fold; the page under it does', (t) async {
    await pumpBarsShell(t, '/pager', _routes);
    await t.drag(find.byKey(const ValueKey('photos')), const Offset(-300, 0));
    await settleChrome(t);
    expect(find.text('photo 1'), findsOneWidget);
    expect(navFolded(t), isFalse);
    await t.drag(find.byKey(const ValueKey('outer')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
  });

  testWidgets('content that cannot scroll never folds', (t) async {
    await pumpBarsShell(t, '/short', _routes);
    await t.drag(find.byKey(const ValueKey('short')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isFalse);
  });

  testWidgets('a route change / tab switch brings the bars back', (t) async {
    final router = await pumpBarsShell(t, '/long', _routes);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    router.go('/routes');
    await settleChrome(t);
    expect(navFolded(t), isFalse);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('screen reader on: never folds', (t) async {
    await pumpBarsShell(t, '/long', _routes, screenReader: true);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -400));
    await settleChrome(t);
    expect(navFolded(t), isFalse);
    expect(t.getSize(find.byType(MgNavBand)).height, 64 + _band);
  });

  testWidgets('reduced motion: the fold is instant (one frame)', (t) async {
    await pumpBarsShell(t, '/long', _routes, reducedMotion: true);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await t.pump();
    await t.pump();
    expect(t.getSize(find.byType(MgNavBand)).height, _band);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, 60));
    await t.pump();
    await t.pump();
    expect(t.getSize(find.byType(MgNavBand)).height, 64 + _band);
  });

  testWidgets('animated fold: 300 ms emphasized, a mid frame in between', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final mid = t.getSize(find.byType(MgNavBand)).height;
    expect(mid, inExclusiveRange(_band, 64 + _band));
    await t.pump(const Duration(milliseconds: 250));
    expect(t.getSize(find.byType(MgNavBand)).height, _band);
  });

  testWidgets('dock + strips + AI button keep the bottom safe area (34) in both states', (t) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
    await pumpBarsShell(t, '/dock', _routes, pending: pending);
    await t.pump(const Duration(milliseconds: 400));
    Rect dock() => t.getRect(find.byType(MgDock));
    final cta = find.byKey(const ValueKey('cta'));
    expect(dock().bottom, _h - 64 - _band, reason: 'dock on the nav');
    final strip = find.byType(MgStatusStrip);
    expect(strip, findsWidgets);
    expect(t.getRect(strip.first).bottom, lessThanOrEqualTo(dock().top));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    expect(dock().bottom, _h - _band, reason: 'dock down to the band — the home indicator stays clear');
    expect(t.getRect(cta).bottom, lessThanOrEqualTo(_h - _band - 10));
    expect(t.getRect(strip.first).bottom, lessThanOrEqualTo(dock().top), reason: 'strips ride on the dock');
    await t.drag(find.byType(CustomScrollView), const Offset(0, 80));
    await settleChrome(t);
    expect(dock().bottom, _h - 64 - _band);
  });

  testWidgets('strips and the AI button without a dock sit on the band, never on the home indicator', (t) async {
    final pending = PendingBooking(id: 'b1', totalPrice: 12027, createdAt: DateTime.now());
    await pumpBarsShell(t, '/', _routes, pending: pending);
    await t.pump(const Duration(milliseconds: 400));
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    final strip = find.byType(MgStatusStrip);
    expect(strip, findsWidgets);
    expect(t.getRect(strip.first).bottom, lessThanOrEqualTo(_h - _band - 8 + 0.5));
    final fab = find.byType(MgAiFab);
    expect(fab, findsOneWidget);
    expect(t.getRect(fab).bottom, lessThanOrEqualTo(_h - _band));
  });

  testWidgets('the shell banner band folds its line (the status-bar strip stays night)', (t) async {
    const b = BannerData(enabled: true, text: 'Velín banner', bg: Color(0xFF000000), color: Color(0xFFFFFFFF));
    await pumpBarsShell(t, '/long', _routes, banner: b);
    final banner = find.byType(MgTopBanner);
    expect(banner, findsOneWidget);
    final open = t.getSize(banner).height;
    expect(open, 47 + MgTopBanner.height);
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, -300));
    await settleChrome(t);
    expect(t.widget<MgTopBanner>(banner).folded, isTrue);
    expect(t.getSize(banner).height, 47, reason: 'only the status-bar strip');
    await t.drag(find.byKey(const ValueKey('long')), const Offset(0, 60));
    await settleChrome(t);
    expect(t.getSize(banner).height, open);
  });

  testWidgets('keyboard rule unchanged: keyboard open = the whole nav off', (t) async {
    await pumpBarsShell(t, '/long', _routes);
    t.view.viewInsets = const FakeViewPadding(bottom: 600);
    await settleChrome(t);
    final slot = find.ancestor(of: find.byType(MgNavBand), matching: find.byType(MgStickySlide));
    expect(t.widget<MgStickySlide>(slot.first).visible, isFalse);
    t.view.resetViewInsets();
    await settleChrome(t);
    expect(t.widget<MgStickySlide>(slot.first).visible, isTrue);
  });

  testWidgets('MgPage pinned back (outside the shell): folds while scrolling down, back on scroll up', (t) async {
    await pumpV2(
      t,
      MgPage(
        header: const SizedBox(height: 300, child: Text('HEADER')),
        sections: [for (var i = 0; i < 30; i++) SizedBox(height: 90, child: Text('s$i'))],
        pinnedBack: () {},
        pinnedTitle: 'PINNED',
      ),
      scaffold: false,
    );
    MgStickySlide slide() =>
        t.widget<MgStickySlide>(find.descendant(of: find.byType(MgPinnedBack), matching: find.byType(MgStickySlide)).first);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await settleChrome(t);
    expect(slide().visible, isFalse, reason: 'scrolling down: the pinned bar stays away');
    await t.drag(find.byType(CustomScrollView), const Offset(0, 60));
    await settleChrome(t);
    expect(slide().visible, isTrue);
    expect(find.text('PINNED'), findsOneWidget);
  });
}
