// verify:render cases — v5.0.1 bike filter: the collapsed card in every
// state (calm, calm + branch, one filter, many filters + branch) and the
// real Motorky screen scrolled to the card (dates only / filters on /
// open), plus a 12-bike fleet count line.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_filter_chips_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';

import '../support/fakes_catalog.dart';
import 'render_harness.dart';

Widget _card(BuildContext context, CatalogFilter f, {String? branch}) => MotoFilterCardV2(
      open: false,
      active: f.filterCount,
      onToggle: () {},
      onReset: () {},
      chips: motoFilterChips(t(context), f, set: (_) {}, branchName: branch),
      body: const SizedBox.shrink(),
    );

/// The four folded states one under the other on the light page.
Widget _states() => Builder(
      builder: (context) => ColoredBox(
        color: MgColors.canvas,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          _card(context, const CatalogFilter()),
          _card(context, const CatalogFilter(branch: 'b'), branch: 'MotoGo24 Mezná'),
          _card(context, const CatalogFilter(licenseGroup: 'A2')),
          _card(
            context,
            const CatalogFilter(
                category: 'naked', licenseGroup: 'A2', minPowerKw: 35, maxPowerKw: 70, maxSeatMm: 820, availableTodayOnly: true, branch: 'b'),
            branch: 'MotoGo24 Velké Němčice',
          ),
        ]),
      ),
    );

Future<void> _toCard(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 300));
  final card = find.byType(MotoFilterCardV2);
  final page = find.byType(Scrollable).first;
  await t.scrollUntilVisible(card, 200, scrollable: page, maxScrolls: 40);
  await t.pump();
  // The card near the top, the count line + first bike under it.
  final top = t.getTopLeft(card).dy;
  await t.drag(page, Offset(0, 110 - top), warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _open(WidgetTester t) async {
  await _toCard(t);
  // The heading row (the chips below it remove a filter).
  await t.tapAt(t.getTopLeft(find.byType(MotoFilterCardV2)) + const Offset(70, 40));
  await t.pump(const Duration(milliseconds: 400));
}

List<Motorcycle> _fleet12() => [
      for (var i = 0; i < 12; i++)
        Motorcycle(
          id: 'f-$i',
          model: kMotos[i % 4].model,
          category: kMotos[i % 4].category,
          branchId: kMotos[i % 2].branchId,
          branchName: kMotos[i % 2].branchName,
          status: 'active',
          branchIsOpen: true,
          prices: kBmw.prices,
        ),
    ];

List<RenderCase> v501FilterCases() {
  final (ws, we) = futureWeekend();
  RenderCase m(String state, List<Override> Function() o, {Future<void> Function(WidgetTester)? after}) =>
      RenderCase('v501f', 'motorky', state, () => const MotorkyScreenV2(), o, after: after ?? _toCard);
  final on = CatalogFilter(category: 'naked', licenseGroup: 'A2', branch: 'b-mezna', startDate: ws, endDate: we);
  return [
    RenderCase('v501f', 'card', 'states', _states, () => const []),
    m('dates_only', () => catalogOverrides(filter: CatalogFilter(startDate: ws, endDate: we), filtered: [kBmw, kHusq, kKids])),
    m('filters_on', () => catalogOverrides(filter: on, filtered: [kHusq])),
    m('filters_open', () => catalogOverrides(filter: on, filtered: [kHusq]), after: _open),
    m('fleet12', () => catalogOverrides(motos: _fleet12())),
  ];
}
