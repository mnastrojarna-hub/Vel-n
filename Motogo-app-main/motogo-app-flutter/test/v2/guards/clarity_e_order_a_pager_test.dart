// Clarity "order-a" P2-10 (new look): in the detail pager the back button
// and the "‹ n / m ›" pill float over the bike; once the bike is scrolled
// past its photo they get a solid band behind them, so they never sit on
// text (they used to cover the price note above the calendar). Layout only:
// the controls, their taps and the hide-on-scroll stay as they were.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_dock_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_pager_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';

import '../support/bars_harness.dart';
import '../support/v2_harness.dart';

final _routes = <String, Widget Function(GoRouterState)>{
  '/search': (_) => const MotorkyScreenV2(),
  '/moto/:id': (s) => MotoDetailScreen(motoId: s.pathParameters['id']!),
};

Future<void> _shot(WidgetTester t, String name) async {
  final dir = Platform.environment['MG_SHOTS_DIR'];
  if (dir == null || dir.isEmpty) return;
  await t.runAsync(() async {
    final layer = t.binding.renderViews.first.debugLayer! as OffsetLayer;
    final ui.Image img = await layer.toImage(Offset.zero & t.view.physicalSize);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

double _bandOpacity(WidgetTester t) => t.widget<AnimatedOpacity>(find.byKey(const ValueKey('detail-pager-band'))).opacity;

void main() {
  setUpAll(loadMontserrat);

  testWidgets('P2-10: scrolled past the photo, the pager controls sit on a solid band', (t) async {
    await pumpBarsShell(t, '/search', _routes, size: const Size(390, 844));
    await t.pump(const Duration(milliseconds: 500));
    final ids = t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false)).ids;
    final z = t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;
    t
        .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
        .position
        .jumpTo(z.offsetOf(1));
    await t.pump();
    await t.tap(find.byKey(ValueKey('mc-${ids[1]}')), warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(MotoDetailPagerV2View), findsOneWidget);
    // On the photo: no band (the photo-style controls as designed).
    expect(_bandOpacity(t), 0);
    final scroll = find.descendant(of: find.byType(MotoDetailPagerV2View), matching: find.byType(CustomScrollView)).first;
    // Down past the photo (controls fold), then a little up (they return).
    await t.drag(scroll, const Offset(0, -900));
    await settleChrome(t);
    await slowDrag(t, scroll, 80);
    await settleChrome(t);
    final back = find.byWidgetPredicate((w) => w is MgV2Back && w.style == MgBackStyle.photo);
    expect(back.hitTestable(), findsOneWidget, reason: 'controls shown again');
    expect(_bandOpacity(t), 1, reason: 'solid band behind the controls over text');
    final band = t.getRect(find.byKey(const ValueKey('detail-pager-band')));
    expect(band.bottom, greaterThanOrEqualTo(t.getRect(back).bottom), reason: 'the band covers the controls');
    await _shot(t, 'e_order_a__detail_pager_band__cs__390x844');
    // Back to the top: the photo again, no band.
    await t.drag(scroll, const Offset(0, 3000));
    await settleChrome(t);
    expect(_bandOpacity(t), 0);
    // "VYBRAT TERMÍN" brings the date step up: its card starts below the band.
    await t.tap(find.descendant(of: find.byType(DetailDockV2), matching: find.byType(MgCta)));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final trip = t.getRect(find.byType(DetailTripCardV2));
    // RD-06: assert the state that occurs — no silent branch.
    final opacity = _bandOpacity(t);
    final bandBottom = t.getRect(find.byKey(const ValueKey('detail-pager-band'))).bottom;
    final controlsBottom = MediaQuery.paddingOf(t.element(find.byType(MotoDetailPagerV2View))).top + 12 + 46;
    // The date step sits under the shown controls → the band is up (state
    // asserted, so this step can fail), and the card starts below both it
    // and the controls.
    expect(opacity, 1, reason: 'controls over text after VYBRAT TERMÍN → solid band');
    expect(trip.top, greaterThanOrEqualTo(bandBottom - 0.5), reason: 'date card below the band');
    expect(trip.top, greaterThanOrEqualTo(controlsBottom - 0.5), reason: 'date card below the controls');
    await _shot(t, 'e_order_a__detail_pager_pick__cs__390x844');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });
}
