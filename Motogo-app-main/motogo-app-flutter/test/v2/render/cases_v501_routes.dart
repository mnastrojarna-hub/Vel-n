// verify:render cases — v5.0.1 Trasy list: one route per screen (photo
// pager with the road preview and the place photos, two place tiles),
// the clear toolbar and the loud "Filtry zapnuté (n)" state. Network
// photos never load in tests → RtCardImage.debugBuilder draws stand-ins.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/reservation_provider.dart';
import 'package:motogo_app/features/routes/places_filter.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/routes_screen.dart';
import 'package:motogo_app/features/routes/v2/route_card_photos_v2.dart';

import '../support/fakes_routes.dart';
import 'render_harness.dart';

/// Stand-in photos: a sky / land gradient per URL + its name.
Widget fakeRoutePhoto(String url) {
  final h = url.hashCode;
  const palettes = [
    [Color(0xFF6FA8DC), Color(0xFF3D7A3A), Color(0xFF20401E)],
    [Color(0xFFF2B36B), Color(0xFFB0563A), Color(0xFF3A2418)],
    [Color(0xFF8EC3E6), Color(0xFF7A8F9C), Color(0xFF2E3B44)],
    [Color(0xFFBFD9A8), Color(0xFF5E8C4A), Color(0xFF1E3318)],
  ];
  final p = palettes[h.abs() % palettes.length];
  return DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: p, stops: const [0, 0.55, 1]),
    ),
    child: Align(
      alignment: const Alignment(0.6, -0.2),
      child: Text(url.split('/').last.replaceAll('.jpg', ''),
          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13, fontWeight: FontWeight.w800)),
    ),
  );
}

RoutePoi _p(RoutePoi p, String img) => RoutePoi(
    id: p.id, name: p.name, lat: p.lat, lng: p.lng, category: p.category, description: p.description, imageUrl: img);

RouteItem _r(RouteItem r, {String? cover, List<RoutePoi>? pois, String? name}) => RouteItem(
      id: r.id,
      branchId: r.branchId,
      name: name ?? r.name,
      routeType: r.routeType,
      distanceKm: r.distanceKm,
      durationMin: r.durationMin,
      difficulty: r.difficulty,
      waypoints: r.waypoints,
      coverImage: cover,
      pois: pois ?? r.pois,
      reviewAvg: r.reviewAvg,
      reviewCount: r.reviewCount,
      countries: r.countries,
    );

/// The fake routes with photos: r1 cover = its monastery photo (as live:
/// the cover is one of its POI photos), every place with a photo.
List<RouteItem> photoRoutes({bool long = false}) {
  final r1 = kRtRoutes[0];
  final pois = [for (final p in r1.pois) _p(p, 'https://img.test/${p.id}-${p.category}.jpg')];
  return [
    _r(r1,
        cover: 'https://img.test/p1-sights.jpg',
        pois: pois,
        name: long ? 'Velký okruh Jižní Moravou: Rajhrad, Židlochovice, Nosislav a vinné sklepy kolem Výhonu' : null),
    _r(kRtRoutes[1], cover: 'https://img.test/r2-cover.jpg', pois: [
      _p(const RoutePoi(id: 'q1', name: 'Věstonická nádrž', category: 'water'), 'https://img.test/q1-water.jpg'),
      _p(const RoutePoi(id: 'q2', name: 'Děvičky', category: 'castle'), 'https://img.test/q2-castle.jpg'),
    ]),
    kRtRoutes[2], // no photos at all → the night fallback
  ];
}

class _Countries extends PlacesFilterNotifier {
  @override
  PlacesFilter build() => const PlacesFilter(countries: {'CZ'});
}

GoRouter Function() _router() => () => GoRouter(initialLocation: '/routes-list', routes: [
      ShellRoute(builder: (_, __, child) => AppShellV2(child: child), routes: [
        GoRoute(path: '/routes-list', builder: (_, __) => const RoutesScreen()),
        GoRoute(path: '/routes/:id', builder: (_, s) => Text('DETAIL ${s.pathParameters['id']}')),
      ]),
    ]);

List<Override> _shell() => [
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      pendingBookingFabProvider.overrideWith((ref) => Stream.value(null)),
      pendingSosFabProvider.overrideWith((ref) => Stream.value(null)),
      docsFabStatusProvider.overrideWith((ref) => Completer<DocsScreenStatus>().future),
      reservationsProvider.overrideWith((ref) => Stream.value(const <Reservation>[])),
    ];

/// Scrolls the page so that route card [i] fills the screen (as a snap).
Future<void> Function(WidgetTester) toCard(int i, {int page = 0}) => (t) async {
      final first = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('route-screen-'));
      if (first.evaluate().isEmpty) return;
      final pos = Scrollable.of(t.element(first.first)).position;
      final dy = t.getTopLeft(first.first).dy;
      final h = t.getSize(first.first).height;
      pos.jumpTo(pos.pixels + dy + h * i);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      if (page > 0) {
        final pv = find.byType(PageView).evaluate().map((e) => e.widget as PageView).toList();
        for (final v in pv) {
          if (v.controller != null && v.controller!.hasClients) {
            final box = t.getRect(find.byWidget(v));
            if (box.top > -10 && box.top < 200) v.controller!.jumpToPage(page);
          }
        }
        await t.pump();
        await t.pump(const Duration(milliseconds: 1200));
      }
    };

Future<void> setUpRoutePhotos() async {
  RtCardImage.debugBuilder = fakeRoutePhoto;
}

List<RenderCase> v501RoutesCases() {
  RenderCase c(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after, bool shell = true}) =>
      RenderCase('v501', 'routes', state, () => const RoutesScreen(), o,
          router: shell ? _router() : null, after: after, end: rtEnd, loading: state == 'loading');
  List<Override> photos({bool long = false}) => [...routesOverrides(routes: photoRoutes(long: long)), ..._shell()];
  return [
    c('top', photos),
    c('card1', photos, after: toCard(0)),
    c('card1_preview', photos, after: toCard(0, page: 1)),
    c('card1_place', photos, after: toCard(0, page: 2)),
    c('card2', photos, after: toCard(1)),
    c('card3_nophoto', photos, after: toCard(2)),
    c('card1_long', () => photos(long: true), after: toCard(1)),
    c('filters_on', () => [...photos(), placesFilterProvider.overrideWith(_Countries.new)]),
    c('loading', () => [...routesOverrides(routesHang: true), ..._shell()]),
    c('bare_card1', () => routesOverrides(routes: photoRoutes()), after: toCard(0), shell: false),
  ];
}
