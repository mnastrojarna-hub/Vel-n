// FND-10: MgPhoto box, photo viewer (zoom, pager, swipe-down, counter,
// dots), hero photo flight, Ken Burns.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_hero_photo.dart';
import 'package:motogo_app/core/v2/motion/mg_ken_burns.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_photo.dart';
import 'package:motogo_app/core/v2/widgets/mg_photo_viewer.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/hero_tags.dart';
import '../support/v2_harness.dart';

List<String> _urls(int n) => [for (var i = 0; i < n; i++) 'https://img.test/p$i.jpg'];

Future<int> _viewer(WidgetTester tester, int n, {bool reduced = false, List<int>? pages}) async {
  var closes = 0;
  await pumpV2(
    tester,
    MgPhotoViewerView(urls: _urls(n), onClose: () => closes++, onPage: pages?.add),
    reducedMotion: reduced,
    scaffold: false,
  );
  await tester.pump();
  return closes;
}

double _scale(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first).transformationController!.value.getMaxScaleOnAxis();

Future<void> _drain(WidgetTester tester) => tester.pump(const Duration(seconds: 11));

/// The dark skeleton shimmers while a photo loads → fixed pumps, no settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(mockPathProvider);
  setUp(MgMotion.resetSession);

  testWidgets('MgPhoto: fixed aspect box, dark placeholder never light', (tester) async {
    await pumpV2(tester, const SizedBox(width: 200, child: MgPhoto(url: '', aspectRatio: 4 / 3, dark: true)));
    expect(tester.getSize(find.byType(MgPhoto)), const Size(200, 150));
    final box = tester.widget<ColoredBox>(find.descendant(of: find.byType(MgPhoto), matching: find.byType(ColoredBox)));
    expect(box.color, const Color(0xFF0E2A1C));
  });

  testWidgets('viewer: double-tap zooms 2.5×, double-tap back to 1×', (tester) async {
    await _viewer(tester, 3);
    final c = tester.getCenter(find.byType(InteractiveViewer).first);
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(c);
    await _settle(tester);
    expect(_scale(tester), closeTo(2.5, 0.01));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(c);
    await _settle(tester);
    expect(_scale(tester), closeTo(1, 0.01));
    await _drain(tester);
  });

  testWidgets('viewer reduced: double-tap lands at once', (tester) async {
    await _viewer(tester, 2, reduced: true);
    final c = tester.getCenter(find.byType(InteractiveViewer).first);
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_scale(tester), closeTo(2.5, 0.01));
    await _drain(tester);
  });

  testWidgets('viewer: swipe = next photo; zoomed fling never pages', (tester) async {
    final pages = <int>[];
    await _viewer(tester, 3, pages: pages);
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await _settle(tester);
    expect(pages, [1]);
    expect(find.text('2 / 3'), findsOneWidget);
    final c = tester.getCenter(find.byType(PageView));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(c);
    await _settle(tester);
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await _settle(tester);
    expect(pages, [1]);
    await _drain(tester);
  });

  testWidgets('viewer: ↓150 at 1× closes, ↓40 stays', (tester) async {
    var closes = 0;
    await pumpV2(tester, MgPhotoViewerView(urls: _urls(2), onClose: () => closes++), scaffold: false);
    await tester.timedDrag(find.byType(PageView), const Offset(0, 40), const Duration(milliseconds: 500));
    await _settle(tester);
    expect(closes, 0);
    await tester.timedDrag(find.byType(PageView), const Offset(0, 150), const Duration(milliseconds: 500));
    await _settle(tester);
    expect(closes, 1);
    await _drain(tester);
  });

  testWidgets('viewer: 5 photos → 5 dots + counter, 9 → no dots', (tester) async {
    await _viewer(tester, 5);
    expect(find.byKey(const ValueKey('mg-viewer-dot-4')), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    await _viewer(tester, 9);
    expect(find.byKey(const ValueKey('mg-viewer-dot-0')), findsNothing);
    expect(find.text('1 / 9'), findsOneWidget);
    await _drain(tester);
  });

  for (final reduced in [false, true]) {
    testWidgets('MgHeroPhoto flies between routes; reduced=$reduced → no flight', (tester) async {
      late BuildContext ctx;
      await pumpV2(
        tester,
        Builder(builder: (c) {
          ctx = c;
          return Center(child: MgHeroPhoto(tag: mgHeroTagMoto(7), child: const SizedBox(width: 80, height: 60, child: ColoredBox(color: Colors.green))));
        }),
        reducedMotion: reduced,
        scaffold: false,
      );
      expectUniqueHeroTags(tester);
      Navigator.of(ctx).push(MaterialPageRoute<void>(
        builder: (_) => Align(
          alignment: Alignment.topCenter,
          child: MgHeroPhoto(tag: mgHeroTagMoto(7), child: const SizedBox(width: 360, height: 240, child: ColoredBox(color: Colors.green))),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final flying = find.byWidgetPredicate((w) => w is ClipRRect && w.borderRadius != BorderRadius.zero);
      expect(find.byType(Hero), reduced ? findsNothing : findsWidgets);
      if (!reduced) expect(flying, findsWidgets);
      await tester.pumpAndSettle();
      expect(mgHeroTagRes('x'), 'res-img-x');
    });
  }

  testWidgets('MgKenBurns: once per session key, static under reduced motion', (tester) async {
    Transform? t(WidgetTester tester) {
      final f = find.descendant(of: find.byType(MgKenBurns), matching: find.byType(Transform));
      return f.evaluate().isEmpty ? null : tester.widget<Transform>(f.first);
    }

    await pumpV2(tester, const MgKenBurns(sessionKey: 'moto-1', child: SizedBox(width: 100, height: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(t(tester)!.transform.getMaxScaleOnAxis(), greaterThan(1.0));
    await tester.pumpAndSettle();
    await pumpV2(tester, const SizedBox());
    await pumpV2(tester, const MgKenBurns(sessionKey: 'moto-1', child: SizedBox(width: 100, height: 100)));
    expect(t(tester), isNull);
    await pumpV2(tester, const MgKenBurns(sessionKey: 'moto-2', child: SizedBox(width: 100, height: 100)), reducedMotion: true);
    expect(t(tester), isNull);
  });
}
