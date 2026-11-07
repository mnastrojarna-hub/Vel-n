// verify:render cases — routes_rides package, navigation body (F-07): the
// OLD navigation widgets drawn in the v2 scope (their seams) over a map-
// coloured backdrop — HUD, next-stop pill, stop reached, route done, fork,
// status banners, stops sheet, end / save dialogs.
import 'package:flutter/material.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart' show VisitResult;
import 'package:motogo_app/features/routes/route_nav_status.dart';
import 'package:motogo_app/features/routes/route_nav_widgets.dart';
import 'package:motogo_app/features/routes/v2/nav/nav_sheets_v2.dart';

import '../support/fakes_rides.dart';
import 'cases_core.dart' show launcher, tapOpen;
import 'render_harness.dart';

Widget _map(List<Widget> top, List<Widget> bottom) => ColoredBox(
      color: const Color(0xFFE8EFE9),
      child: Stack(children: [
        Positioned(left: 16, right: 16, top: 60, child: Column(children: top)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: bottom),
        ),
        Positioned(
          right: 16,
          bottom: 300,
          child: Column(children: [
            NavCompassButton(rotationDeg: 30, onTap: () {}),
          ]),
        ),
      ]),
    );

Widget _hud({double? rem = 15900}) =>
    NavHud(remainingM: rem, speedKmh: 64, altitude: 205, fraction: 0.6, etaMinutes: 21);

Widget _pad(Widget w) => Padding(padding: const EdgeInsets.fromLTRB(12, 0, 64, 12), child: w);

List<RenderCase> routesNavUxCases() => [
      RenderCase('rrux', 'nav', 'ride',
          () => _map(const [], [
                _pad(Align(
                    alignment: Alignment.centerLeft,
                    child: NavNextStopPill(name: 'Klášter Rajhrad', distanceM: 3200, progress: '3/5', onTap: () {}))),
                _hud(),
              ]),
          () => ridesOverrides()),
      RenderCase('rrux', 'nav', 'reached',
          () => _map(const [], [
                _pad(StopReachedCard(
                  name: 'Klášter Rajhrad',
                  visit: const VisitResult(firstVisit: true, totalPlaces: 13),
                  nextLabel: 'Blučina',
                  onNext: () {},
                  onChoose: () {},
                  onClose: () {},
                  onRate: () {},
                )),
                _hud(),
              ]),
          () => ridesOverrides()),
      RenderCase('rrux', 'nav', 'done',
          () => _map(const [], [
                _pad(RouteDoneCard(canRate: true, canSave: false, onRate: () {}, onSave: () {}, onClose: () {})),
                _hud(rem: 10),
              ]),
          () => ridesOverrides()),
      RenderCase('rrux', 'nav', 'fork',
          () => _map(const [], [
                _pad(NavForkHint(leftLabel: 'Výhon u Židlochovic', rightLabel: 'Blučina', nextIsLeft: false, onTap: () {})),
                _hud(),
              ]),
          () => ridesOverrides()),
      RenderCase('rrux', 'nav', 'status',
          () => _map([
                const NavStatusBanner(status: NavStatus.gpsLost),
                const SizedBox(height: 10),
                NavStatusBanner(status: NavStatus.denied, onRequest: () {}),
                const SizedBox(height: 10),
                const NavStatusBanner(status: NavStatus.straightLine),
              ], [_hud()]),
          () => ridesOverrides()),
      RenderCase('rrux', 'nav', 'stops',
          () => launcher((c) => showNavStopsSheet(c,
              stops: const [
                NavStopView(index: 0, label: 'Nosislav – vinné sklepy', reached: true, isNext: false, hasPoi: true),
                NavStopView(index: 1, label: 'Zámek Židlochovice', reached: true, isNext: false, hasPoi: true),
                NavStopView(index: 2, label: 'Klášter Rajhrad', reached: false, isNext: true, hasPoi: true),
                NavStopView(index: 3, label: 'Blučina', reached: false, isNext: false, hasPoi: true),
              ],
              onNavigateTo: (_) {},
              branchLabel: 'MotoGo24 · Velké Němčice',
              onNavigateToBranch: () {})),
          () => ridesOverrides(),
          after: tapOpen),
      RenderCase('rrux', 'nav', 'end-dialog', () => launcher((c) => showDialog<bool>(context: c, builder: navEndDialogV2)),
          () => ridesOverrides(), after: tapOpen),
      RenderCase('rrux', 'nav', 'save-dialog',
          () => launcher((c) => showDialog<bool>(context: c, builder: (dc) => navSaveDialogV2(dc, TextEditingController(text: 'Moje vyjížďka')))),
          () => ridesOverrides(), after: tapOpen),
    ];
