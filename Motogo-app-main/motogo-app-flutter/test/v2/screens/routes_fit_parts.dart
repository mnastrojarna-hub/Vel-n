// Parts of the Trasy fit matrix (routes_fit_matrix_test.dart): every
// category / community / route subtitle and long distance on a place card,
// the whole filter band with every category chip, the location prompt and
// the route stat cards for every difficulty × route type × pager.
import 'package:flutter/material.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/poi_categories.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:motogo_app/features/routes/v2/place_card_v2.dart';
import 'package:motogo_app/features/routes/v2/places_filters_v2.dart';
import 'package:motogo_app/features/routes/v2/places_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/poi_cat_icon_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_parts_v2.dart';

import '../support/fakes_routes.dart';

const _dists = ['850 m', '12.3 km · 15m', '128.5 km · 2h 47m'];

/// One card per category label (catalog), community and route subtitle;
/// long distances + rating; one selected with its order badge.
Widget placeCardsPart() => Builder(builder: (context) {
      final tr = t(context);
      final cards = <Widget>[];
      var i = 0;
      for (final c in kPoiCats) {
        final poi = RoutePoi(
            id: 'k${c.key}', name: 'Rozhledna Hustopeče a okolí', category: c.key, isCatalogPoi: true,
            avgRating: i.isEven ? 4.6 : null, ratingCount: i.isEven ? 128 : 0);
        cards.add(PlaceCardV2(
            poi: poi,
            name: poi.name,
            subtitle: tr.tr(c.i18nKey),
            subKind: PlaceSubKind.category,
            dist: _dists[i % 3],
            selected: i == 2,
            order: i == 2 ? 12 : null,
            onTap: () {},
            onToggle: () {}));
        i++;
      }
      const u = RoutePoi(id: 'u', name: 'Vyhlídka nad Pouzdřany', isUserPoi: true, avgRating: 5, ratingCount: 3);
      cards.add(PlaceCardV2(
          poi: u, name: u.name, subtitle: tr.tr('poiCommunityPoint'), subKind: PlaceSubKind.community,
          dist: _dists[2], selected: false, onTap: () {}, onToggle: () {}));
      final r = kRtRoutes[2];
      cards.add(PlaceCardV2(
          poi: kCatalog.first, name: kCatalog.first.name, subtitle: r.name, subKind: PlaceSubKind.route,
          dist: _dists[1], selected: true, order: 3, onTap: () {}, onToggle: () {}));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
    });

/// The white filter band: toolbar (active filters, nearby + km, route,
/// clear) and every category chip with a 4-digit count.
Widget placesFiltersPart() => Builder(builder: (context) {
      final tr = t(context);
      return PlacesFiltersV2(
        activeCount: 3,
        onTools: () {},
        nearbyOn: true,
        nearbyKm: 25,
        kmOptions: const [5, 10, 25, 50],
        onNearby: () {},
        onKm: (_) {},
        routeLabel: kRtRoutes[1].name,
        routeActive: true,
        routeCount: 12,
        onRoute: () {},
        onClear: () {},
        cats: [
          for (final c in kPoiCats)
            PlacesCatV2(
                key: c.key,
                label: tr.tr(c.i18nKey),
                count: 1234,
                selected: c.key == 'lookout',
                icon: PoiCatIconV2(c.key, color: const Color(0xFF0D6E0D))),
        ],
        onCat: (_) {},
        sourceCount: 4321,
      );
    });

Widget locationPromptPart() => PlacesLocationPromptV2(onTap: () {});

/// Stat cards: every difficulty × loop / via-places, with and without the
/// sibling pager, + the "Místa na trase" cards at their real height.
Widget detailCardsPart() => Builder(builder: (context) {
      final out = <Widget>[];
      var n = 0;
      for (final d in ['easy', 'medium', 'hard']) {
        for (final type in ['loop', 'poi']) {
          final r = RouteItem(
              id: 'x$n', name: 'Vyhlídková jízda: Stará radnice v Brně a okolí', routeType: type, difficulty: d,
              pois: kRtRoutes.first.pois, reviewAvg: 4.8, reviewCount: 1234);
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RouteStatsCardV2(
              route: r,
              name: r.name,
              startLine: 'MotoGo24 Velké Němčice',
              km: '1249 km',
              time: '12 h 55 min',
              fromMe: '128 km · 1 h 47 min',
              sibling: n.isEven ? (12, 34) : null,
              onPrev: () {},
              onNext: () {},
            ),
          ));
          n++;
        }
      }
      final pois = kRtRoutes.first.pois;
      out.add(SizedBox(
        height: RoutePoiCardV2.heightFor(MediaQuery.textScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: pois.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => RoutePoiCardV2(poi: pois[i], number: i + 1, lang: 'cs', active: i == 0, onTap: () {}),
        ),
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
    });
