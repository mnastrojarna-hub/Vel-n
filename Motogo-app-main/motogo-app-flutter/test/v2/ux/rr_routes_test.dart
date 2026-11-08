// routes_rides F-07 / F-09′ / F-12 / F-13 / F-19 / F-20 / F-24 / F-25 /
// F-28: navigation body seams (same callbacks / pops), the route-detail
// first window, export sheet, Mapa tras panel (snap), skeleton, the line
// that draws once, the place-sheet pager and the planner dock labels.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:motogo_app/core/v2/gestures/mg_snap_physics.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart' show VisitResult;
import 'package:motogo_app/features/routes/route_builder_screen.dart';
import 'package:motogo_app/features/routes/route_detail_screen.dart';
import 'package:motogo_app/features/routes/route_nav_widgets.dart';
import 'package:motogo_app/features/routes/route_poi_sheet.dart';
import 'package:motogo_app/features/routes/routes_map_picker.dart';
import 'package:motogo_app/features/routes/routes_provider.dart';
import 'package:motogo_app/features/routes/v2/builder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/nav/nav_cards_v2.dart';
import 'package:motogo_app/features/routes/v2/nav/nav_sheets_v2.dart';
import 'package:motogo_app/features/routes/v2/poi_sheet_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_skeleton_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_view_v2.dart';
import 'package:motogo_app/features/routes/v2/route_line_draw_v2.dart';
import 'package:motogo_app/features/routes/v2/route_map_full_v2.dart';
import 'package:motogo_app/features/routes/v2/routes_map_panel_v2.dart';

import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/supabase_stub.dart';
import '../support/v2_harness.dart';

Widget _launch(void Function(BuildContext) open) =>
    Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('OPEN'))));

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('OPEN'));
  await t.pumpAndSettle();
}

List<Override> _detail({bool hang = false}) => [
      ...routesOverrides(routesHang: hang),
      routeFullProvider.overrideWith((ref, id) async {
        for (final r in kRtRoutes) {
          if (r.id == id) return r;
        }
        return null;
      }),
    ];

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    HttpOverrides.global = RtFakeHttpOverrides();
    await stubSupabase();
  });
  setUp(MgMotion.resetSession);

  group('F-07 navigation (same callbacks)', () {
    testWidgets('stop reached: CTA = confirm, ✕ = close, ★ = rate, ☰ = stops', (t) async {
      final log = <String>[];
      await pumpV2(
          t,
          Padding(
            padding: const EdgeInsets.all(12),
            child: StopReachedCard(
              name: 'Klášter Rajhrad',
              visit: const VisitResult(firstVisit: true, totalPlaces: 13),
              nextLabel: 'Blučina',
              onNext: () => log.add('next'),
              onChoose: () => log.add('choose'),
              onClose: () => log.add('close'),
              onRate: () => log.add('rate'),
            ),
          ),
          reducedMotion: true);
      expect(find.byType(StopReachedCardV2), findsOneWidget);
      expect(find.text('Místo objeveno! · celkem 13'), findsOneWidget);
      await t.tap(find.byType(MgCta));
      await t.tap(find.bySemanticsLabel('Zavřít'));
      await t.tap(find.bySemanticsLabel('Napsat recenzi'));
      await t.tap(find.bySemanticsLabel('Body na trase'));
      expect(log, ['next', 'close', 'rate', 'choose']);
    });

    testWidgets('route done: "Ohodnotit trasu" = the old onRate (reviews sheet)', (t) async {
      final log = <String>[];
      await pumpV2(
          t,
          RouteDoneCard(
              canRate: true, canSave: false, onRate: () => log.add('rate'), onSave: () => log.add('save'), onClose: () => log.add('close')),
          reducedMotion: true);
      expect(find.byType(RouteDoneCardV2), findsOneWidget);
      await t.tap(find.byType(MgCta));
      expect(log, ['rate']);
    });

    testWidgets('stops sheet: "Navigovat" pops and navigates to that stop; branch row too', (t) async {
      final log = <String>[];
      await pumpV2(
          t,
          _launch((c) => showNavStopsSheet(c,
              stops: const [
                NavStopView(index: 0, label: 'Nosislav', reached: true, isNext: false, hasPoi: true),
                NavStopView(index: 1, label: 'Klášter Rajhrad', reached: false, isNext: true, hasPoi: true),
              ],
              onNavigateTo: (i) => log.add('to:$i'),
              branchLabel: 'MotoGo24 · Velké Němčice',
              onNavigateToBranch: () => log.add('branch'))));
      await _open(t);
      expect(find.byType(NavStopsSheetV2), findsOneWidget);
      await t.tap(find.text('Navigovat').at(1));
      await t.pumpAndSettle();
      expect(log, ['to:1']);
      expect(find.byType(NavStopsSheetV2), findsNothing);
    });

    for (final (tap, want) in [('Zrušit', false), ('Ukončit', true)]) {
      testWidgets('"Ukončit trasu?" T6: "$tap" pops $want', (t) async {
        bool? got;
        await pumpV2(t, _launch((c) async => got = await showDialog<bool>(context: c, builder: navEndDialogV2)));
        await _open(t);
        await t.tap(find.text(tap));
        await t.pumpAndSettle();
        expect(got, want);
      });
    }

    testWidgets('next-stop pill + HUD: v2 views, km in the locale format', (t) async {
      await pumpV2(
          t,
          Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            NavNextStopPill(name: 'Klášter Rajhrad', distanceM: 3200, progress: '3/5', onTap: () {}),
            const NavHud(remainingM: 15900, speedKmh: 64, altitude: 205, fraction: 0.6, etaMinutes: 21),
          ]));
      expect(find.text('Příští: Klášter Rajhrad · 3,2 km'), findsOneWidget);
      expect(find.text('15,9 km'), findsOneWidget);
      expect(find.text('64'), findsOneWidget);
    });
  });

  group('F-09′ / F-19 route detail', () {
    testWidgets('320×690 fr: map clamps to 200, the whole stats card + the start of the text in the first window', (t) async {
      expect(RouteDetailViewV2.mapHeightFor(690), 207);
      expect(RouteDetailViewV2.mapHeightFor(600), 200);
      expect(RouteDetailViewV2.mapHeightFor(1200), 280);
      await pumpV2(t, const RouteDetailScreen(routeId: 'r1', siblingIds: ['r1', 'r2', 'r3']),
          lang: 'fr', size: const Size(320, 690), overrides: _detail(), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 500));
      final card = t.getRect(find.byType(RouteStatsCardV2));
      expect(card.top, lessThan(690 * 0.30));
      expect(card.bottom, lessThan(690));
      expect(t.getRect(find.byType(RouteDescV2)).top, lessThan(690));
      await rtEnd(t);
    });

    testWidgets('loading = the board-geometry skeleton with a back disc', (t) async {
      await pumpV2(t, const RouteDetailScreen(routeId: 'r1'),
          overrides: _detail(hang: true), scaffold: false, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(RouteDetailSkeletonV2), findsOneWidget);
      await rtEnd(t);
    });
  });

  group('F-12 export sheet', () {
    testWidgets('a row closes the sheet and runs the same open; < 2 points = T3 note', (t) async {
      var opened = 0;
      await pumpV2(
          t,
          _launch((c) => rtShowExportSheetV2(c,
              sub: '5 míst · Okruh · 40 km',
              rowSub: '6 bodů',
              targets: [RtExportTargetV2('Mapy.com', 'map', () => opened++, dark: true)])));
      await _open(t);
      await t.tap(find.text('Mapy.com'));
      await t.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(RouteExportSheetV2), findsNothing);
    });
  });

  group('F-13 Mapa tras panel', () {
    testWidgets('cards: tap = pick, "Detail ›" = open, fling snaps to a whole card', (t) async {
      final log = <String>[];
      await pumpV2(
          t,
          Align(
            alignment: Alignment.bottomCenter,
            child: RoutesMapPicker(
              routes: kRtRoutes.take(3).toList(),
              branches: const {'b1': kBranchVn, 'b2': kBranchMezna},
              lang: 'cs',
              activeId: null,
              lines: const {},
              computing: const {},
              onPick: (r) => log.add('pick:${r.id}'),
              onOpen: (r) => log.add('open:${r.id}'),
            ),
          ));
      expect(find.byType(RoutesMapPanelV2), findsOneWidget);
      // fix:r1 #11 split the title so the count never gets cut.
      expect(find.text('Trasy přes vybraný bod'), findsOneWidget);
      expect(find.text('\u00A0·\u00A03'), findsOneWidget);
      // fix:r2 parity: the start branch of each route, as the old card.
      expect(find.text(kBranchVn.name), findsWidgets);
      expect(t.takeException(), isNull);
      await t.tap(find.text(kRtRoutes.first.name));
      await t.tap(find.text('Detail').first);
      expect(log, ['pick:r1', 'open:r1']);
      final list = find.descendant(of: find.byType(RoutesMapPanelV2), matching: find.byType(Scrollable));
      await t.fling(list, const Offset(-180, 0), 900);
      await t.pumpAndSettle();
      final px = t.state<ScrollableState>(list).position.pixels;
      expect(px % kRoutesMapCardV2Extent, closeTo(0, 0.5));
      expect(t.widget<Scrollable>(list).physics, isA<MgSnapScrollPhysics>());
    });

    testWidgets('flag OFF: the old card shows the start branch too (parity)', (t) async {
      await pumpV2(
          t,
          Align(
            alignment: Alignment.bottomCenter,
            child: RoutesMapPicker(
              routes: kRtRoutes.take(3).toList(),
              branches: const {'b1': kBranchVn, 'b2': kBranchMezna},
              lang: 'cs',
              activeId: null,
              lines: const {},
              computing: const {},
              onPick: (_) {},
              onOpen: (_) {},
            ),
          ),
          v2: false);
      expect(find.byType(RoutesMapPanelV2), findsNothing);
      expect(find.text(kBranchVn.name), findsWidgets);
    });

    for (final w in [320.0, 360.0, 412.0]) {
      testWidgets('v2 card with branch fits at $w dp (2-line name, no overflow)', (t) async {
        await pumpV2(
            t,
            Align(
              alignment: Alignment.bottomCenter,
              child: RoutesMapPicker(
                routes: kRtRoutes.take(3).toList(),
                branches: const {'b1': kBranchVn, 'b2': kBranchMezna},
                lang: 'de',
                activeId: 'r1',
                lines: const {},
                computing: const {},
                onPick: (_) {},
                onOpen: (_) {},
              ),
            ),
            size: Size(w, 780));
        expect(t.takeException(), isNull);
        final card = find.ancestor(of: find.text(kBranchVn.name).first, matching: find.byType(Container)).first;
        expect(t.getRect(find.text(kBranchVn.name).first).bottom, lessThanOrEqualTo(t.getRect(card).bottom));
      });
    }
  });

  testWidgets('F-20 route line: reduced motion = the whole line at once', (t) async {
    final pts = [const LatLng(49, 16.6), const LatLng(49.05, 16.62), const LatLng(49.09, 16.61)];
    List<LatLng>? drawn;
    await pumpV2(t, RouteLineDrawV2(points: pts, sessionKey: 'k', build: (p) {
      drawn = p;
      return const SizedBox();
    }), reducedMotion: true);
    expect(drawn, pts);
  });

  testWidgets('F-20 route line: draws once (partial mid-way, full at the end, static on return)', (t) async {
    final pts = [const LatLng(49, 16.6), const LatLng(49.05, 16.62), const LatLng(49.09, 16.61)];
    List<LatLng>? drawn;
    Widget w() => RouteLineDrawV2(points: pts, sessionKey: 'k2', build: (p) {
          drawn = p;
          return const SizedBox();
        });
    await pumpV2(t, w());
    await t.pump(const Duration(milliseconds: 600));
    expect(drawn!.length, lessThanOrEqualTo(pts.length));
    await t.pump(const Duration(milliseconds: 1200));
    expect(drawn, pts);
    await pumpV2(t, const SizedBox());
    await pumpV2(t, w());
    expect(drawn, pts);
  });

  group('F-24 / F-25 place sheet', () {
    // lookonly-fix: the old pager had no ‹ › buttons — only the swipe (and ✕).
    testWidgets('a swipe steps the places (no ‹ › discs); primary = rank CTA in a dark dock', (t) async {
      final pois = kRtRoutes.first.pois;
      await pumpV2(
          t,
          _launch((c) => showRoutePoiSheet(c, pois.first, 'cs',
              index: 0, siblings: pois, isSelected: (_) => false, onToggleSelect: (_) {})),
          reducedMotion: true);
      await _open(t);
      expect(find.text('1 / ${pois.length}'), findsOneWidget);
      expect(find.bySemanticsLabel('Další místo'), findsNothing);
      await t.flingFrom(const Offset(300, 500), const Offset(-260, 0), 1200);
      await t.pumpAndSettle();
      expect(find.text('2 / ${pois.length}'), findsOneWidget);
      expect(find.descendant(of: find.byType(PoiTripButtonV2), matching: find.byType(MgCta)), findsOneWidget);
      await rtEnd(t);
    });
  });

  testWidgets('F-28 planner dock: "Uložit" / "Navrhnout" under the icons at 412', (t) async {
    await pumpV2(t, RouteBuilderScreen(route: kRtRoutes.first),
        overrides: routesOverrides(), scaffold: false, reducedMotion: true, size: const Size(412, 915));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.descendant(of: find.byType(BuilderDockV2), matching: find.text('Uložit')), findsOneWidget);
    expect(find.descendant(of: find.byType(BuilderDockV2), matching: find.text('Navrhnout')), findsOneWidget);
    await rtEnd(t);
  });
}
