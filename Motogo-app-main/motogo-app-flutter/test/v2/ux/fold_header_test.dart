// Fixed v2 top headers fold with the hide-on-scroll bars (owner 2026-11-08
// "celá ta hlavička … ta pevná část, aby se při scrollování zabalovala"):
// `MgFoldHeader` folds to a status-bar strip while the content scrolls
// down and comes back on any scroll up, inside the shell (the shell's bars)
// and on a root route (`MgBarsHost`'s own); the header's folding height
// raises the scroll range needed before anything folds. Wired on the edit
// of a reservation, the route / POI submit form, the ride and trip detail
// and the payment-methods loading state.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_app_bar.dart';
import 'package:motogo_app/core/v2/chrome/mg_fold_header.dart';
import 'package:motogo_app/core/v2/chrome/mg_hide_on_scroll.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_bar.dart';
import 'package:motogo_app/features/payment/v2/payment_methods_view_v2.dart';
import 'package:motogo_app/features/routes/ride_trip_api.dart' show RideTripOpResult;
import 'package:motogo_app/features/routes/v2/rides/trip_detail_view_v2.dart';
import 'package:motogo_app/features/routes/v2/submit_form_v2.dart';

import '../screens/reservations_cases.dart' show editView;
import '../screens/rides_cases.dart' show rideDetail, ridesMockPathProvider;
import '../support/bars_harness.dart';
import '../support/fakes_reservations.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

const _top = 47.0;

Widget _rows(String key, int n) => ListView.builder(
      key: ValueKey(key),
      itemCount: n,
      itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$key $i')),
    );

Widget _generic(GoRouterState? _) => Scaffold(
      body: MgBarsHost(
        child: Column(children: [
          MgFoldHeader(child: MgAppBar(title: 'Titulek', onBack: () {})),
          Expanded(child: _rows('fold-list', 60)),
        ]),
      ),
    );

double _header(WidgetTester t) => t.getSize(find.byType(MgFoldHeader)).height;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// A finger drag (no fling) from [y] on the screen.
Future<void> _drag(WidgetTester t, double y, double dy) async {
  final g = await t.startGesture(Offset(200, y));
  for (var i = 0; i < 10; i++) {
    await g.moveBy(Offset(0, dy / 10));
    await t.pump(const Duration(milliseconds: 16));
  }
  await t.pump(const Duration(milliseconds: 300));
  await g.up();
  await _settle(t);
}

Future<void> _root(WidgetTester t, Widget w, {List<Override> overrides = const []}) async {
  await t.pumpWidget(const SizedBox());
  t.view.padding = const FakeViewPadding(top: _top * 2, bottom: 68);
  t.view.viewPadding = const FakeViewPadding(top: _top * 2, bottom: 68);
  await pumpV2(t, w, size: const Size(390, 844), scaffold: false, overrides: overrides);
  await _settle(t);
}

ScrollUpdateNotification _upd(BuildContext ctx, double px, double max) => ScrollUpdateNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: max,
        pixels: px,
        viewportDimension: 600,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 2,
      ),
      context: ctx,
      scrollDelta: 40,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -40)),
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    registerRidesStrings();
    ridesMockPathProvider();
    // Map tiles answer 200 with a tiny PNG (the default test client: 400).
    HttpOverrides.global = RtFakeHttpOverrides();
  });

  testWidgets('in the shell: the header folds to the status-bar strip and back; the body grows', (t) async {
    await pumpBarsShell(t, '/fold', {'/fold': _generic});
    final h = _header(t);
    expect(h, greaterThan(_top + 40));
    await t.drag(find.byKey(const ValueKey('fold-list')), const Offset(0, -300));
    await settleChrome(t);
    expect(navFolded(t), isTrue);
    expect(_header(t), _top, reason: 'only the status-bar strip stays');
    expect(t.getRect(find.byKey(const ValueKey('fold-list'))).top, _top);
    // The strip keeps light icons on the night surface.
    final bar = t.widget<MgStatusBar>(find.ancestor(of: find.byType(MgFoldHeader), matching: find.byType(MgStatusBar)).first);
    expect(bar.dark, isFalse, reason: 'the page canvas above, not the strip');
    expect(t.widget<MgStatusBar>(find.descendant(of: find.byType(MgFoldHeader), matching: find.byType(MgStatusBar)).first).dark, isTrue);
    // Folded = no taps / semantics on the header.
    expect(find.text('Titulek').hitTestable(), findsNothing);
    await t.drag(find.byKey(const ValueKey('fold-list')), const Offset(0, 60));
    await settleChrome(t);
    expect(_header(t), h);
    expect(navFolded(t), isFalse);
    expect(find.text('Titulek').hitTestable(), findsOneWidget);
  });

  testWidgets('on a root route the screen folds its own header (no shell)', (t) async {
    await _root(t, _generic(null));
    final h = _header(t);
    await t.drag(find.byKey(const ValueKey('fold-list')), const Offset(0, -300));
    await _settle(t);
    expect(_header(t), _top);
    await t.drag(find.byKey(const ValueKey('fold-list')), const Offset(0, 60));
    await _settle(t);
    expect(_header(t), h);
  });

  testWidgets('a folding header raises the range needed before anything folds (only while its route is on top)', (t) async {
    await t.pumpWidget(const SizedBox());
    final ctx = t.element(find.byType(SizedBox));
    final plain = MgBarsController();
    addTearDown(plain.dispose);
    plain.handle(_upd(ctx, 100, 250));
    expect(plain.hidden, isTrue, reason: 'range 250 ≥ 200');
    final c = MgBarsController();
    addTearDown(c.dispose);
    var on = true;
    c.reportFold(#h, 143, () => on);
    c.handle(_upd(ctx, 100, 250));
    expect(c.hidden, isFalse, reason: '250 < 200 + 143: it would stop scrolling once folded');
    c.handle(_upd(ctx, 140, 400));
    expect(c.hidden, isTrue);
    c.show();
    on = false;
    c.handle(_upd(ctx, 100, 250));
    expect(c.hidden, isTrue, reason: 'a covered page header does not count');
  });

  testWidgets('wired: reservation edit (shell), submit form, ride / trip detail, payment methods loading', (t) async {
    final b = resv('d1', status: 'reserved', from: 5, to: 7);
    await pumpBarsShell(t, '/edit', {'/edit': (_) => editView(b)});
    await _settle(t);
    final h = _header(t);
    expect(h, greaterThan(150), reason: 'the tall edit header');
    await _drag(t, 600, -300);
    expect(_header(t), _top);
    await _drag(t, 600, 60);
    expect(_header(t), h);

    final cases = <String, (Widget, List<Override>)>{
      'submit': (
        SubmitScaffoldV2(
          title: 'Návrh místa',
          busy: false,
          busyLabel: '',
          onSubmit: () {},
          children: [for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('f$i'))],
        ),
        const []
      ),
      'ride': (rideDetail(kRideMg), ridesOverrides()),
      'trip': (
        TripDetailViewV2(
          trip: tripOf(kTripRides(), 't1'),
          name: 'Výlet',
          busy: false,
          error: RideTripOpResult.unavailable,
          onBack: () {},
          onRename: () {},
          onShare: () {},
          onDelete: () {},
          onSplit: () {},
          onVisibility: (_) {},
        ),
        tripOverrides()
      ),
      'payment-loading': (
        PaymentMethodsViewV2(
          cards: null,
          body: _rows('pm-list', 30),
          onBack: () {},
          onRefresh: () async {},
          onDelete: (_) {},
          onSetDefault: (_) {},
          onAdd: null,
          emptyNote: '',
        ),
        const []
      ),
    };
    for (final e in cases.entries) {
      await _root(t, e.value.$1, overrides: e.value.$2);
      expect(find.byType(MgFoldHeader), findsOneWidget, reason: e.key);
      final h = _header(t);
      await _drag(t, 640, -300);
      expect(_header(t), _top, reason: '${e.key}: folded');
      await _drag(t, 640, 60);
      expect(_header(t), h, reason: '${e.key}: back');
    }
  });
}
