// v5.0.1 Trasy list repair (critics): a route without photos shows the
// LARGE road preview as its only page (no camera "1 / n", no corner
// sketch); short phones drop the place tiles (their photos stay pager
// pages); "Nevidíš všechny trasy" only for a filter that hides routes;
// the Trasy list's record action is the quiet secondary button.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/routes/v2/record_dock_v2.dart';
import 'package:motogo_app/features/routes/v2/route_card_full_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/route_card_full_v2.dart';
import 'package:motogo_app/features/routes/v2/route_card_photos_v2.dart';
import 'package:motogo_app/features/routes/v2/routes_filters_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_v501_routes.dart' show fakeRoutePhoto, photoRoutes;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_rides.dart' show ridesOverrides;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _tr(String k) => translations['cs']![k]!;

Widget _card(int i, double h) => SingleChildScrollView(
      child: RouteCardFullV2(
        route: photoRoutes()[i],
        branch: null,
        lang: 'cs',
        approach: null,
        onTap: () {},
        onReviews: () {},
        height: h,
      ),
    );

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
    RtCardImage.debugBuilder = fakeRoutePhoto;
  });
  tearDownAll(() => RtCardImage.debugBuilder = null);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  testWidgets('no photo: the road preview is the only page, no camera count', (t) async {
    expect(routeCardPhotos(photoRoutes()[2]), isEmpty);
    await pumpV2(t, _card(2, 800), size: const Size(360, 800), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(RtCountPill), findsNothing);
    expect(find.byType(RtSmallSketch), findsNothing);
    expect(find.byType(RtSketchPage), findsOneWidget);
    expect(find.text(_tr('rtListPreview').toUpperCase()), findsOneWidget);
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, 1);
    await rtEnd(t);
  });

  testWidgets('tall card: place tiles; short card: no tiles, photo pages stay', (t) async {
    await pumpV2(t, _card(0, 860), size: const Size(360, 860), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(RtPlaceTile), findsNWidgets(2));
    final pages = t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount;
    await rtEnd(t);

    await pumpV2(t, _card(0, 640), size: const Size(320, 640), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(RtPlaceTile), findsNothing);
    expect(find.byType(RtCountPill), findsOneWidget);
    expect(t.widget<PageView>(find.byType(PageView)).childrenDelegate.estimatedChildCount, pages);
    await rtEnd(t);
  });

  testWidgets('"Nevidíš všechny trasy" only when a filter hides routes', (t) async {
    Widget card(bool narrowing) => RoutesActiveFiltersV2(
          count: 1,
          chips: [RtFilterChipItem('Řadit: A–Z', () {})],
          onClear: () {},
          narrowing: narrowing,
        );
    await pumpV2(t, card(false));
    expect(find.text(_tr('rtListFltHint')), findsNothing);
    expect(find.text(_tr('rtListFltOn').replaceAll('{n}', '1')), findsOneWidget);
    await pumpV2(t, card(true));
    expect(find.text(_tr('rtListFltHint')), findsOneWidget);
  });

  testWidgets('toolbar: the sort value and an icon-only map fit at 320 px', (t) async {
    await pumpV2(
      t,
      RoutesToolbarV2(
        activeCount: 2,
        sortLabel: 'Sortieren: In meiner Nähe',
        sortValue: 'In meiner Nähe',
        sortOn: true,
        onFilter: () {},
        onSort: () {},
        onMap: () {},
        onClear: () {},
      ),
      size: const Size(320, 640),
      lang: 'de',
    );
    expect(t.takeException(), isNull);
    final map = t.getRect(find.byKey(const ValueKey('rt-tool-map')));
    expect(map.right, lessThanOrEqualTo(320));
    expect(map.width, 44);
    expect(find.text(translations['de']!['routesMapBtn']!), findsNothing);
  });

  testWidgets('quiet record dock: same caps label, not the big CTA', (t) async {
    await pumpV2(t, const TrasyRecordDockV2(quiet: true), overrides: ridesOverrides());
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('ZAZNAMENAT JÍZDU'), findsOneWidget);
    expect(find.byType(MgCta), findsNothing);
  });
}
