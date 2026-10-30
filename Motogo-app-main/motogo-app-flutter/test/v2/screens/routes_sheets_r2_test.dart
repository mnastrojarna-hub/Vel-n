// fix:routes:r2 — the Místa / Trasy tool sheets got the v2 chrome (44 px ✕,
// well chips, ink "Zobrazit (n)"); behaviour must stay the same in BOTH
// looks: a category / country / sort / route pick reaches the same filter
// state, "Zobrazit (n)" applies, "Zrušit" resets.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/all_pois_screen.dart';
import 'package:motogo_app/features/routes/country_codes.dart';
import 'package:motogo_app/features/routes/places_filter.dart';
import 'package:motogo_app/features/routes/routes_screen.dart';
import 'package:motogo_app/features/routes/v2/places_parts_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

String _tr(String k) => translations['cs']![k]!;

Finder _textWhere(bool Function(String s) test) =>
    find.byWidgetPredicate((w) => w is Text && w.data != null && test(w.data!));

Future<void> _tap(WidgetTester t, Finder f) async {
  expect(f, findsWidgets);
  await t.ensureVisible(f.last);
  await t.pump();
  await t.tap(f.last, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Entry buttons: a plain tap (ensureVisible would scroll the collapsing
/// header and the tap would miss).
Future<void> _open(WidgetTester t, Finder f) async {
  expect(f, findsWidgets);
  await t.tap(f.last);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Old Místa keeps its tool chips in a collapsed panel ("Filtry a řazení").
Future<void> _oldPanel(WidgetTester t) async {
  await _open(t, find.text(_tr('poiFiltersOpen')));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100)); // panel + its auto-scroll
  }
}

/// Old Místa: a tall surface — on a phone the panel's auto-scroll (>140 px)
/// closes it again before a test tap lands.
Size _placesSize(bool v2) => Size(412, v2 ? 915 : 2000);

Finder _tool(String icon) => find.byWidgetPredicate((w) => w is TrasyToolChipV2 && w.icon == icon);

PlacesFilter _filter(WidgetTester t, Type screen) =>
    ProviderScope.containerOf(t.element(find.byType(screen))).read(placesFilterProvider);

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  for (final v2 in [true, false]) {
    final look = v2 ? 'v2' : 'old';

    testWidgets('$look: Místa tools — category applies, reset clears', (t) async {
      await pumpV2(t, const AllPoisScreen(asTab: true), size: _placesSize(v2), overrides: routesOverrides(), v2: v2);
      await t.pump(const Duration(seconds: 1));
      final open = v2 ? _tool(MgIcons.filter) : find.text(_tr('sortNearMe'));
      if (!v2) await _oldPanel(t);
      await _open(t, open);
      expect(find.text(_tr('poiToolsTitle')), findsOneWidget);
      await _tap(t, _textWhere((s) => s.endsWith(_tr('poiCatCastle'))));
      await _tap(t, _textWhere((s) => s.startsWith('${_tr('poiFilterApply')} (')));
      expect(find.text(_tr('poiToolsTitle')), findsNothing);
      expect(_filter(t, AllPoisScreen).cats, {'castle'});
      await _open(t, open);
      await _tap(t, find.text(_tr('routesFilterClear')));
      expect(find.text(_tr('poiToolsTitle')), findsNothing);
      expect(_filter(t, AllPoisScreen).cats, isEmpty);
      await rtEnd(t);
    });

    testWidgets('$look: Místa route picker — a route filters the list', (t) async {
      await pumpV2(t, const AllPoisScreen(asTab: true), size: _placesSize(v2), overrides: routesOverrides(), v2: v2);
      await t.pump(const Duration(seconds: 1));
      if (!v2) await _oldPanel(t);
      await _open(t, v2 ? _tool(MgIcons.route) : find.text(_tr('poiRoutePick')));
      final r = kRtRoutes.first;
      await _tap(t, find.text(r.nameFor('cs')));
      expect(find.text(_tr('poiRoutePickTitle')), findsNothing);
      expect(_filter(t, AllPoisScreen).routeId, r.id);
      await rtEnd(t);
    });

    testWidgets('$look: Trasy filter — country applies; sort picks', (t) async {
      await pumpV2(t, const RoutesScreen(), size: const Size(412, 915), overrides: routesOverrides(), v2: v2);
      await t.pump(const Duration(seconds: 1));
      await _open(t, v2 ? _tool(MgIcons.filter) : find.text(_tr('routesFilter')));
      expect(find.text(_tr('routesFilterTitle')), findsOneWidget);
      await _tap(t, find.text(countryChipLabel('AT')));
      await _tap(t, _textWhere((s) => s.startsWith('${_tr('routesFilterApply')} (')));
      expect(find.text(_tr('routesFilterTitle')), findsNothing);
      expect(_filter(t, RoutesScreen).countries, {'AT'});
      await _open(t, v2 ? _tool(MgIcons.sort) : _textWhere((s) => s.startsWith('${_tr('sortTitle')}: ')));
      await _tap(t, find.text(_tr('sortLength')));
      expect(find.text(_tr('sortLength')), findsNothing, reason: 'sheet closed');
      expect(_textWhere((s) => s.contains(_tr('sortLength'))), findsWidgets);
      await rtEnd(t);
    });
  }
}
