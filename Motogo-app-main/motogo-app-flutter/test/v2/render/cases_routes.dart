// verify:render cases — Trasy v2 (routes_cases*.dart): Místa (list, no
// location, selection, recording manual / rental + weak GPS, loading,
// error, empty, picker, from route), Trasy list states, route detail
// (ok / no POIs / hard abroad / missing / loading / error), planner,
// community forms, maps, nav skin pieces + the "+" add menu.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';

import '../screens/routes_cases.dart' as a;
import '../screens/routes_cases2.dart' as b;
import '../support/fakes_routes.dart';
import 'render_harness.dart';

Future<void> _openAddMenu(WidgetTester t) async {
  final h = t.ensureSemantics();
  try {
    final lang = Localizations.localeOf(t.element(find.byType(Directionality).first)).languageCode;
    final f = find.bySemanticsLabel(translations[lang]!['v2RtAddA11y']!);
    if (f.evaluate().isEmpty) return;
    await t.tap(f.first, warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  } finally {
    h.dispose();
  }
}

List<RenderCase> routesRenderCases() {
  final out = <RenderCase>[];
  void add(String screen, Map<String, a.RtCaseT> m) {
    for (final e in m.entries) {
      out.add(RenderCase('routes', screen, e.key, e.value.$1, e.value.$2,
          loading: e.key.contains('loading'), end: rtEnd));
    }
  }

  add('places', a.placesCases());
  add('routes', a.routesListCases());
  add('detail', b.detailCases());
  add('builder', b.builderCases());
  add('form', b.formCases());
  add('map', b.mapCases());
  add('pieces', b.pieceCases());
  final list = a.placesCases()['list']!;
  out.add(RenderCase('routes', 'places', 'add-menu', list.$1, list.$2, after: _openAddMenu, end: rtEnd));
  return out;
}
