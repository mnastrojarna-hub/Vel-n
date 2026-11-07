// verify:render cases — routes_rides package (F-*): route reviews (section,
// empty, sheet, editor), place rating + reviews, photo viewer, ride result
// sheets, "Odesláno", full route map + "Otevřít v jiné aplikaci", the
// route detail skeleton. Recorder / stop confirm / detail screens come from
// cases_rides.dart / cases_routes.dart.
import 'package:flutter/material.dart';
import 'package:motogo_app/features/routes/route_export.dart';
import 'package:motogo_app/features/routes/routes_map_picker.dart';
import 'package:motogo_app/features/routes/v2/poi_reviews_v2.dart';
import 'package:motogo_app/features/routes/v2/review_editor_v2.dart';
import 'package:motogo_app/features/routes/v2/route_detail_skeleton_v2.dart';
import 'package:motogo_app/features/routes/v2/route_map_full_v2.dart';
import 'package:motogo_app/features/routes/v2/route_reviews_v2.dart';
import 'package:motogo_app/features/routes/v2/rt_photo_viewer_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/ride_results_v2.dart';
import 'package:motogo_app/features/routes/v2/submit_success_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart' show RideStartResult;

import '../support/fakes_rides.dart';
import '../support/fakes_routes.dart' show kRtRoutes;
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

const kRrReviews = <Map<String, dynamic>>[
  {'rating': 5, 'author': 'Motorkář', 'review_text': 'Pohodová vyjížďka, cestou pěkné zastávky a skoro žádný provoz.'},
  {'rating': 4, 'author': 'Jana K.', 'review_text': 'Fajn trasa na odpoledne, místy horší asfalt.'},
  {'rating': 5, 'is_mine': true, 'review_text': ''},
];

const kRrData = RtReviewsData(avg: 4.7, count: 3, my: {'rating': 5}, reviews: kRrReviews, loading: false);
const kRrEmpty = RtReviewsData(avg: null, count: 0, my: null, reviews: [], loading: false);

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.only(top: 24, bottom: 24), child: child);

Widget _editor() => Align(
      alignment: Alignment.bottomCenter,
      child: ReviewEditorV2(
        title: 'Napsat recenzi',
        rating: 4,
        onRate: (_) {},
        controller: TextEditingController(),
        photoCount: 2,
        onPick: () {},
        busy: false,
        onSubmit: () {},
      ),
    );

Widget _poi() => _scroll(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        PoiRatingV2(shown: 0, avg: null, count: 0, mine: null, busy: false, onRate: (_) {}),
        const SizedBox(height: 22),
        PoiReviewsSectionV2(data: kRrEmpty, onWrite: () {}, onDelete: () {}),
      ]),
    ));

Widget _export({bool error = false}) => Align(
      alignment: Alignment.bottomCenter,
      child: RouteExportSheetV2(
        sub: '5 míst · Okruh · 40 km',
        rowSub: error ? null : 'Okruh od bodu nejblíž tobě · 6 bodů',
        error: error ? 'Trasa nemá dostatek bodů pro navigaci' : null,
        targets: [
          if (!error)
            for (final tg in RouteExport.targets())
              RtExportTargetV2(tg.label, rtExportIcon(tg), () {}, dark: tg == RouteExportTarget.mapy),
        ],
      ),
    );

RenderCase _sheet(String state, void Function(BuildContext) open) =>
    RenderCase('rrux', 'result', state, () => launcher(open), () => ridesOverrides(), after: tapOpen);

List<RenderCase> routesRidesUxCases() => [
      RenderCase('rrux', 'reviews', 'section',
          () => _scroll(RouteReviewsSectionV2(data: kRrData, onWrite: () {}, onDelete: () {})), () => ridesOverrides()),
      RenderCase('rrux', 'reviews', 'empty',
          () => _scroll(RouteReviewsSectionV2(data: kRrEmpty, onWrite: () {}, onDelete: () {})), () => ridesOverrides()),
      RenderCase('rrux', 'reviews', 'sheet',
          () => Align(
              alignment: Alignment.bottomCenter,
              child: RouteReviewsSheetV2(routeName: 'Rajhrad a Židlochovicko', data: kRrData, onWrite: () {})),
          () => ridesOverrides()),
      RenderCase('rrux', 'reviews', 'editor', _editor, () => ridesOverrides()),
      RenderCase('rrux', 'poi', 'rating', _poi, () => ridesOverrides()),
      RenderCase('rrux', 'viewer', 'photos',
          () => RtPhotoViewerV2(urls: const ['https://x.invalid/a.jpg', 'https://x.invalid/b.jpg', 'https://x.invalid/c.jpg'],
              initial: 1, onClose: () {}, credit: (_, __) {}),
          () => ridesOverrides(),
          scaffold: false),
      _sheet('saved', (c) => showRideStopResultV2(c, true)),
      _sheet('too-short', (c) => showRideStopResultV2(c, false)),
      _sheet('offline', (c) => showRideStopResultV2(c, null)),
      _sheet('not-signed-in', (c) => showRideStartResultV2(c, RideStartResult.notSignedIn)),
      _sheet('location-off', (c) => showRideStartResultV2(c, RideStartResult.locationOff)),
      _sheet('no-permission', (c) => showRideStartResultV2(c, RideStartResult.noPermission)),
      _sheet('imprecise', (c) => showRideStartResultV2(c, RideStartResult.imprecise)),
      _sheet('failed', (c) => showRideStartResultV2(c, RideStartResult.failed, onRetry: () {})),
      RenderCase('rrux', 'dialog', 'submitted', () => launcher((c) => showSubmitSuccessV2(c)), () => ridesOverrides(),
          after: tapOpen),
      RenderCase('rrux', 'map', 'full',
          () => RouteFullMapV2(
              map: const ColoredBox(color: Color(0xFFE8EFE9)),
              title: 'Rajhrad a Židlochovicko',
              sub: '5 míst · Okruh · 40 km',
              onClose: () {}),
          () => ridesOverrides(),
          scaffold: false),
      RenderCase('rrux', 'sheet', 'export', _export, () => ridesOverrides()),
      RenderCase('rrux', 'sheet', 'export-error', () => _export(error: true), () => ridesOverrides()),
      RenderCase(
          'rrux',
          'map',
          'panel',
          () => Align(
                alignment: Alignment.bottomCenter,
                child: RoutesMapPicker(
                  routes: kRtRoutes.take(3).toList(),
                  branches: const {},
                  lang: 'cs',
                  activeId: kRtRoutes.first.id,
                  lines: const {},
                  computing: const {},
                  onPick: (_) {},
                  onOpen: (_) {},
                ),
              ),
          () => ridesOverrides()),
      RenderCase('rrux', 'detail', 'skeleton', () => RouteDetailSkeletonV2(onBack: () {}, onRetry: () {}),
          () => ridesOverrides(),
          scaffold: false, loading: true),
    ];
