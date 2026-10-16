// verify:render cases — gaps of the per-area matrices: unknown deep link
// page (v2 T1), the full POI detail sheet (v2 head / counter / trip
// button), the old filter / sort / route-picker sheets reached from the v2
// Místa + Trasy screens, the bike detail "Více" toggles opened, and the
// rank ramp (Home funnel + Profil hub at every level 0–20).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/widgets/route_error_page.dart';
import 'package:motogo_app/features/catalog/moto_detail_page.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/routes/all_pois_screen.dart';
import 'package:motogo_app/features/routes/route_poi_sheet.dart';
import 'package:motogo_app/features/routes/routes_screen.dart';
import 'package:motogo_app/features/routes/v2/places_parts_v2.dart';

import '../support/fakes_catalog.dart';
import '../support/fakes_home.dart' show homeOverrides, loyaltyAt;
import '../support/fakes_profile.dart' show profileOverrides;
import '../support/fakes_routes.dart';
import '../support/profile_harness.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

String _lang(WidgetTester t) => Localizations.localeOf(t.element(find.byType(Directionality).first)).languageCode;

Future<void> _tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _chip(String icon) => find.byWidgetPredicate((w) => w is TrasyToolChipV2 && w.icon == icon);

Future<void> _moreToggles(WidgetTester t) async {
  final l = _lang(t);
  for (final k in ['v2DetAllParams', 'v2DetPriceByDay']) {
    await _tap(t, find.text(translations[l]?[k] ?? k));
  }
}

List<RenderCase> extraRenderCases() {
  final route = kRtRoutes.first;
  final pois = route.pois;
  return [
    RenderCase('core', 'route_error', 'unknown_link', () => const SizedBox(), () => const [],
        router: () => GoRouter(
              initialLocation: '/neznamy/odkaz?x=1',
              routes: [GoRoute(path: '/', builder: (_, __) => const SizedBox())],
              errorBuilder: (_, s) => RouteErrorPage(state: s),
            )),
    RenderCase(
        'routes',
        'poi_sheet',
        'route_poi',
        () => launcher((c) => showRoutePoiSheet(c, pois.first, Localizations.localeOf(c).languageCode,
            index: 0, siblings: pois, isSelected: (_) => false, onToggleSelect: (_) {})),
        () => routesOverrides(),
        after: tapOpen,
        end: rtEnd),
    RenderCase(
        'routes',
        'poi_sheet',
        'catalog_selected',
        () => launcher((c) => showRoutePoiSheet(c, kCatalog.first, Localizations.localeOf(c).languageCode,
            siblings: kCatalog, isSelected: (_) => true, onToggleSelect: (_) {})),
        () => routesOverrides(),
        after: tapOpen,
        end: rtEnd),
    RenderCase('routes', 'places', 'filter-sheet', () => const AllPoisScreen(asTab: true), () => routesOverrides(),
        after: (t) => _tap(t, _chip(MgIcons.filter)), end: rtEnd),
    RenderCase('routes', 'places', 'route-picker-sheet', () => const AllPoisScreen(asTab: true), () => routesOverrides(),
        after: (t) => _tap(t, _chip(MgIcons.route)), end: rtEnd),
    RenderCase('routes', 'routes', 'filter-sheet', () => const RoutesScreen(), () => routesOverrides(),
        after: (t) => _tap(t, _chip(MgIcons.filter)), end: rtEnd),
    RenderCase('routes', 'routes', 'sort-sheet', () => const RoutesScreen(), () => routesOverrides(),
        after: (t) => _tap(t, _chip(MgIcons.sort)), end: rtEnd),
    RenderCase('catalog', 'detail', 'more_open', () => const MotoDetailPage(motoId: 'm-bmw', showBackButton: true),
        () => catalogOverrides(), after: _moreToggles),
    for (var l = 0; l <= 20; l++)
      RenderCase('rank', 'home_funnel', 'lvl$l', () => const HomeScreenV2(),
          () => homeOverrides(loyalty: l == 0 ? null : loyaltyAt(l)), level: l),
    for (var l = 0; l <= 20; l++)
      RenderCase('rank', 'profile_hub', 'lvl$l', () => const PfHubHarness(),
          () => profileOverrides(loyalty: l == 0 ? null : loyaltyAt(l)), level: l),
  ];
}
