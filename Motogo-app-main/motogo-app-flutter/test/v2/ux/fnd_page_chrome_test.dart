// FND-14 MgPage (iOS overscroll colour, pinned bar, adaptive refresh),
// FND-15 sticky slide, status strip "+n", nav slot on /sos, FAB motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/motion/mg_sticky_slide.dart';
import 'package:motogo_app/core/v2/shell/shell_nav_map.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';

import '../support/shell_harness.dart';
import '../support/v2_harness.dart';

Widget _page({ScrollController? c, Color? overscroll, Widget? bar, Future<void> Function()? refresh}) => MgPage(
      controller: c,
      overscrollColor: overscroll,
      pinnedBar: bar,
      onRefresh: refresh,
      header: const SizedBox(height: 200, child: ColoredBox(color: MgColors.night)),
      sections: [for (var i = 0; i < 20; i++) SizedBox(height: 80, child: Text('section $i'))],
    );

Widget _ios(Widget child) => Theme(data: ThemeData(platform: TargetPlatform.iOS), child: child);

void main() {
  setUpAll(loadMontserrat);

  testWidgets('iOS rubber-band above a dark header shows the header colour', (tester) async {
    final c = ScrollController();
    await pumpV2(tester, _ios(_page(c: c, overscroll: MgColors.night)), scaffold: false);
    await tester.pump();
    final g = await tester.startGesture(const Offset(180, 300));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(c.offset, lessThan(-40));
    final backdrop = find.byKey(const ValueKey('mg-page-overscroll'));
    final r = tester.getRect(backdrop);
    expect(r.top, 0);
    expect(r.bottom, closeTo(200 - c.offset, 1));
    await g.up();
    await tester.pumpAndSettle();
    await tester.drag(find.text('section 4'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(backdrop).height, 0, reason: 'light sections never sit on a dark backdrop');
  });

  for (final reduced in [false, true]) {
    testWidgets('pinnedBar: hidden at the top, slides in past the header (reduced=$reduced)', (tester) async {
      final c = ScrollController();
      await pumpV2(tester, _page(c: c, bar: const SizedBox(height: 56, child: Text('BAR'))), scaffold: false, reducedMotion: reduced);
      await tester.pump();
      MgStickySlide slide() => tester.widget<MgStickySlide>(find.ancestor(of: find.text('BAR'), matching: find.byType(MgStickySlide)));
      expect(slide().visible, isFalse);
      c.jumpTo(400);
      await tester.pump();
      expect(slide().visible, isTrue);
      final slides = tester.widgetList<AnimatedSlide>(find.ancestor(of: find.text('BAR'), matching: find.byType(AnimatedSlide)));
      expect(slides.first.duration, reduced ? Duration.zero : const Duration(milliseconds: 300));
      c.jumpTo(0);
      await tester.pump();
      expect(slide().visible, isFalse);
    });
  }

  testWidgets('iOS pull-to-refresh is the adaptive spinner, Android the neon disc', (tester) async {
    await pumpV2(tester, _ios(_page(refresh: () async {})), scaffold: false);
    expect(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).color, MgColors.neon);
    await pumpV2(tester, _page(refresh: () async {}), scaffold: false);
    expect(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).backgroundColor, MgColors.neon);
  });

  testWidgets('MgStickySlide collapse: height 0 when hidden, back when shown', (tester) async {
    final v = ValueNotifier(true);
    await pumpV2(
      tester,
      Column(children: [
        ValueListenableBuilder<bool>(
          valueListenable: v,
          builder: (_, on, __) => MgStickySlide(visible: on, collapse: true, child: const SizedBox(height: 64, child: Text('NAV'))),
        ),
      ]),
    );
    expect(tester.getSize(find.byType(MgStickySlide)).height, 64);
    v.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final mid = tester.getSize(find.byType(MgStickySlide)).height;
    expect(mid, inExclusiveRange(0, 64));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byType(MgStickySlide)).height, 0);
    v.value = true;
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MgStickySlide)).height, 64);
  });

  testWidgets('status strip "+2" chip calls onMore', (tester) async {
    var more = 0, taps = 0;
    await pumpV2(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: MgStatusStrip(kind: MgStripKind.pay, title: 'Dokončit rezervaci', onTap: () => taps++, more: 2, onMore: () => more++),
      ),
    );
    expect(find.text('+2'), findsOneWidget);
    await tester.tap(find.text('+2'));
    await tester.pump();
    expect((more, taps), (1, 0));
  });

  group('shell nav slot', () {
    test('AI button only on Domů (old app); the nav slot never depends on the route', () {
      for (final p in ['/sos', '/sos/theft', '/sos/done', '/cart', '/voucher', '/shop/abc', '/shop', '/', '/sos/payment', '/checkout', '/booking', '/payment']) {
        expect(v2FabHiddenFor(p), p == '/' ? isFalse : isTrue, reason: p);
      }
    });

    for (final at in ['/sos', '/sos/theft', '/cart', '/voucher', '/shop/abc']) {
      testWidgets('$at keeps the nav: one tap to Profil', (tester) async {
        await pumpShellV2(tester, at, prefs: const {'mg_v2_ai_coach_seen': true});
        final slot = find.ancestor(of: find.byType(V2NavBar), matching: find.byType(MgStickySlide));
        expect(tester.widget<MgStickySlide>(slot).visible, isTrue);
        expect(tester.getSize(slot).height, greaterThan(60));
        await tester.tap(find.text('Profil'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('PAGE /profile'), findsOneWidget);
      });
    }

    for (final reduced in [false, true]) {
      testWidgets('/checkout keeps the nav slot, as the old shell (reduced=$reduced)', (tester) async {
        final router = await pumpShellV2(tester, '/', reducedMotion: reduced, paths: [...kShellTestPaths, '/checkout']);
        final slot = find.ancestor(of: find.byType(V2NavBar), matching: find.byType(MgStickySlide));
        expect(tester.getSize(slot).height, greaterThan(60));
        router.go('/checkout');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('PAGE /checkout'), findsOneWidget);
        expect(tester.getSize(slot).height, greaterThan(60));
        expect(tester.widget<MgStickySlide>(slot).visible, isTrue);
      });
    }

    testWidgets('the AI button moves with an animated bottom', (tester) async {
      await pumpShellV2(tester, '/');
      final pos = find.ancestor(of: find.byType(MgAiFab), matching: find.byType(AnimatedPositioned));
      expect(pos, findsOneWidget);
      expect(tester.widget<AnimatedPositioned>(pos).duration, const Duration(milliseconds: 300));
    });
  });
}
