// v5.0.1 Trasy list (owner): one route per screen with a photo pager
// (cover → large road preview → place photos, "1 / n"), two place tiles,
// no "Okruh / Za místy" pill on the list card, clear toolbar controls and a
// loud "Filtry zapnuté (n)" card whose ✕ / "Zrušit vše" clear the filters.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/places_filter.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_screen.dart';
import 'package:motogo_app/features/routes/v2/route_card_full_v2.dart';
import 'package:motogo_app/features/routes/v2/route_card_photos_v2.dart';
import 'package:motogo_app/features/routes/v2/route_card_v2.dart' show RouteTypePillV2;
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_v501_routes.dart' show fakeRoutePhoto, photoRoutes;
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _tr(String k) => translations['cs']![k]!;

class _Countries extends PlacesFilterNotifier {
  @override
  PlacesFilter build() => const PlacesFilter(countries: {'CZ'});
}

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

  group('routeCardPhotos', () {
    final r1 = photoRoutes().first;

    test('cover first, then places of OTHER kinds than the cover, every URL once', () {
      final p = routeCardPhotos(r1);
      expect(p.first.url, r1.cover);
      expect(p.first.place, isNull);
      expect(p.map((x) => x.url).toSet().length, p.length);
      // Cover = the monastery (sights): the tiles start with other kinds.
      final picks = routeCardPicks(p);
      expect(picks.map((x) => x.place!.id), ['p3', 'p4']);
    });

    test('no photos → empty; max is respected', () {
      expect(routeCardPhotos(kRtRoutes[2]), isEmpty);
      expect(routeCardPhotos(r1, max: 3).length, 3);
    });

    test('route images[] come after the places', () {
      const r = RouteItem(id: 'x', name: 'x', coverImage: 'a', images: ['a', 'b', 'c']);
      expect(routeCardPhotos(r).map((p) => p.url), ['a', 'b', 'c']);
    });
  });

  testWidgets('one route per screen: full-height cards, pager, tiles, no type pill', (t) async {
    await pumpV2(t, const RoutesScreen(), size: const Size(412, 915), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    final cards = find.byType(RouteCardFullV2);
    expect(cards, findsWidgets);
    expect(t.getSize(cards.first).height, greaterThanOrEqualTo(915));
    expect(find.byType(RouteTypePillV2), findsNothing);
    // The card shows its photo counter and the two place tiles.
    expect(find.textContaining(' / '), findsWidgets);
    // The nearest route (r2) comes first: its two places as tiles.
    expect(find.text('Věstonická nádrž'), findsWidgets);
    expect(find.text('Děvičky'), findsWidgets);
    expect(find.text(_tr('rtListOpen')), findsWidgets);
    await rtEnd(t);
  });

  testWidgets('a tap on a place tile shows that photo in the pager', (t) async {
    await pumpV2(t, const RoutesScreen(), size: const Size(412, 915), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    final tile = find.byKey(const ValueKey('rt-tile-r2-0'));
    // Bring the first card to the top of the screen (as a snap would).
    final card = find.byKey(const ValueKey('route-screen-r2'));
    final pos = Scrollable.of(t.element(card)).position;
    pos.jumpTo(pos.pixels + t.getTopLeft(card).dy);
    await t.pump();
    await t.tap(tile, warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    // Page 3 of 4: cover, preview, then the first place photo.
    expect(find.text('3 / 4'), findsOneWidget);
    await rtEnd(t);
  });

  testWidgets('active filters: loud card, ✕ removes, "Zrušit vše" clears', (t) async {
    await pumpV2(t, const RoutesScreen(),
        size: const Size(412, 915),
        overrides: [...routesOverrides(routes: photoRoutes()), placesFilterProvider.overrideWith(_Countries.new)]);
    await t.pump(const Duration(seconds: 1));
    expect(find.text(_tr('rtListFltOn').replaceAll('{n}', '1')), findsOneWidget);
    expect(find.text(_tr('rtListFltHint')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('rt-filters-clear')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('rt-filters-on')), findsNothing);
    final c = ProviderScope.containerOf(t.element(find.byType(RoutesScreen)));
    expect(c.read(placesFilterProvider).countries, isEmpty);
    await rtEnd(t);
  });

  testWidgets('without filters there is no filter card, the toolbar controls are there', (t) async {
    await pumpV2(t, const RoutesScreen(), size: const Size(412, 915), overrides: routesOverrides());
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('rt-filters-on')), findsNothing);
    for (final k in ['rt-tool-filter', 'rt-tool-sort', 'rt-tool-map']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    await rtEnd(t);
  });

  testWidgets('a fast swipe up moves exactly one route', (t) async {
    await pumpV2(t, const RoutesScreen(), size: const Size(412, 915), overrides: routesOverrides(routes: photoRoutes()));
    await t.pump(const Duration(seconds: 1));
    final first = find.byKey(const ValueKey('route-screen-r2'));
    final pos = Scrollable.of(t.element(first)).position;
    pos.jumpTo(pos.pixels + t.getTopLeft(first).dy);
    await t.pump();
    final start = pos.pixels;
    final extent = t.getSize(first).height;
    await t.flingFrom(const Offset(206, 300), const Offset(0, -500), 30000);
    // Loops on the page (the live dot) never settle: pump the snap out.
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(pos.pixels, closeTo(start + extent, 1));
    await rtEnd(t);
  });
}
