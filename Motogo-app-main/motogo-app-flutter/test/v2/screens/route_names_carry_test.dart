// „Nic nevyplňovat dvakrát“ v editoru trasy (majitel 2026-10-22): po
// „Uložit trasu“ se list „Navrhnout do komunity“ předvyplní uloženým
// názvem a popisem (a naopak), uložená trasa z Mých zážitků nese svůj název,
// obecné „Vlastní vyjížďka“ se nepředvyplňuje. Nový vzhled i starý vzhled;
// předvyplněné listy v 8 jazycích × 2 velikostech bez přetečení.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/i18n/translations.dart' show translations;
import 'package:motogo_app/core/supabase_client.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart' show BuilderStopSpec;
import 'package:motogo_app/features/routes/route_builder_screen.dart';
import 'package:motogo_app/features/routes/route_builder_sheets.dart';
import 'package:motogo_app/features/routes/routes_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';

const _a = RoutePoi(id: 'c1', name: 'Zámek Velké Němčice', lat: 48.9930, lng: 16.6720, isCatalogPoi: true);
const _b = RoutePoi(id: 'c3', name: 'Knížecí les', lat: 49.0040, lng: 16.6790, isCatalogPoi: true);

/// Vlastní trasa z výběru míst (Místa → „Naplánovat trasu“).
RouteItem _custom(String name) => RouteItem(
    id: 'custom', name: name, routeType: 'poi', waypoints: [_a.latLng!, _b.latLng!], pois: const [_a, _b]);

final _calls = <http.Request>[];

/// Jen volání uložení / návrhu (ostatní dotazy appky se nepočítají).
Iterable<http.Request> get _writes =>
    _calls.where((c) => c.url.path.contains('/rpc/save_user_route') || c.url.path.endsWith('/rest/v1/routes'));

Future<http.Response> _api(http.Request r) async {
  _calls.add(r);
  final p = r.url.path;
  if (p.endsWith('/rpc/save_user_route')) {
    return http.Response(jsonEncode({'success': !r.body.contains('FAIL')}), 200, request: r);
  }
  if (p.endsWith('/rest/v1/routes') && r.method == 'POST') return http.Response('', 201, request: r);
  return http.Response('[]', 200, request: r, headers: {'content-type': 'application/json'});
}

String _tr(String lang, String key) => translations[lang]?[key] ?? translations['cs']![key]!;

TextField _field(WidgetTester tester, int i) => tester.widget<TextField>(find.byType(TextField).at(i));

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Zavře zobrazenou hlášku (jinak by další čekala ve frontě / kryla dok).
Future<void> _hideSnack(WidgetTester tester) async {
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).removeCurrentSnackBar();
  await _frames(tester);
}

Future<void> _openSave(WidgetTester tester, bool v2) async {
  await tester.tap(v2 ? find.byTooltip(_tr('cs', 'routeSaveTitle')) : find.byIcon(Icons.bookmark_add_outlined));
  await _frames(tester);
}

Future<void> _openSuggest(WidgetTester tester, bool v2) async {
  await tester.tap(v2 ? find.byTooltip(_tr('cs', 'routeSuggestBtn')) : find.text(_tr('cs', 'routeSuggestBtn')));
  await _frames(tester);
}

Future<void> _fillAndSend(WidgetTester tester, String sendKey, String name, String desc) async {
  await tester.enterText(find.byType(TextField).at(0), name);
  await tester.enterText(find.byType(TextField).at(1), desc);
  await tester.tap(find.widgetWithText(ElevatedButton, _tr('cs', sendKey)));
  await _frames(tester);
}

Future<void> _pumpBuilder(WidgetTester tester, Widget screen, {bool v2 = true}) async {
  await pumpV2(tester, screen, size: const Size(412, 915), overrides: routesOverrides(), v2: v2, scaffold: false);
  await _frames(tester);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerRoutesStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: MotoGoSupabase.url,
      publishableKey: 'test-anon',
      httpClient: MockClient(_api),
      authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
      debug: false,
    );
    await Supabase.instance.client.auth.setInitialSession(jsonEncode({
      'access_token': 'test-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'r',
      'user': {'id': 'u-1', 'aud': 'authenticated', 'app_metadata': {}, 'created_at': '2026-01-01T00:00:00Z'},
    }));
  });
  setUp(() {
    _calls.clear();
    MgMotion.resetSession();
  });

  group('RouteNameMemory.fromRoute', () {
    test('katalogová trasa → její název, popis katalogu ne', () {
      const r = RouteItem(id: 'r1', name: 'Pálava', description: 'Katalogový popis');
      final m = RouteNameMemory.fromRoute(r, ownStops: false);
      expect((m.name, m.desc), ('Pálava', ''));
    });
    test('nová vlastní trasa a obecný popisek (všech 8 jazyků) → prázdné', () {
      expect(RouteNameMemory.fromRoute(_custom(''), ownStops: false).name, '');
      for (final lang in kV2Langs) {
        final generic = _tr(lang, 'poiCustomRouteTitle');
        expect(RouteNameMemory.fromRoute(_custom(generic), ownStops: true).name, '', reason: lang);
        expect(RouteNameMemory.fromRoute(_custom(generic), ownStops: false).name, '', reason: lang);
      }
    });
    test('uložená trasa z Mých zážitků → její název (a popis)', () {
      final r = RouteItem(id: 'custom', name: 'Šumava víkend', description: 'Přes Kvildu', waypoints: [_a.latLng!]);
      final m = RouteNameMemory.fromRoute(r, ownStops: true);
      expect((m.name, m.desc), ('Šumava víkend', 'Přes Kvildu'));
      m.remember('Nový', 'Popis');
      expect((m.name, m.desc), ('Nový', 'Popis'));
    });
  });

  for (final v2 in [true, false]) {
    final look = v2 ? 'v2' : 'starý vzhled';
    testWidgets('$look: Uložit → Navrhnout má název i popis předvyplněné', (tester) async {
      await _pumpBuilder(tester, RouteBuilderScreen(route: _custom(_tr('cs', 'poiCustomRouteTitle'))), v2: v2);
      await _openSave(tester, v2);
      // Obecné „Vlastní vyjížďka“ se nepředvyplňuje (jako dosud).
      expect(_field(tester, 0).controller!.text, '');
      await _fillAndSend(tester, 'routeSaveBtn', 'Šumava víkend', 'Přes Kvildu');
      final save = _writes.single;
      expect(jsonDecode(save.body)['p_name'], 'Šumava víkend');
      expect(find.byType(TextField), findsNothing); // list se zavřel
      expect(find.text(_tr('cs', 'routeSaved')), findsOneWidget);
      await _hideSnack(tester);

      await _openSuggest(tester, v2);
      expect(find.text(_tr('cs', 'routeSuggestTitle')), findsOneWidget);
      expect(_field(tester, 0).controller!.text, 'Šumava víkend');
      expect(_field(tester, 1).controller!.text, 'Přes Kvildu');
      // Odeslat beze změny → návrh nese uložené hodnoty.
      await tester.tap(find.widgetWithText(ElevatedButton, _tr('cs', 'poiSubmitSend')));
      await _frames(tester);
      final ins = _writes.last;
      expect(ins.method, 'POST');
      final body = jsonDecode(ins.body);
      final row = body is List ? body.first : body;
      expect((row['name'], row['description']), ('Šumava víkend', 'Přes Kvildu'));
      await rtEnd(tester);
    });
  }

  testWidgets('Navrhnout → Uložit má název i popis předvyplněné', (tester) async {
    await _pumpBuilder(tester, RouteBuilderScreen(route: _custom('')));
    await _openSuggest(tester, true);
    expect(_field(tester, 0).controller!.text, '');
    await _fillAndSend(tester, 'poiSubmitSend', 'Pálava za soumraku', 'Vinné sklepy');
    await tester.tap(find.widgetWithText(ElevatedButton, _tr('cs', 'submitSuccessOk')));
    await _frames(tester);
    await _openSave(tester, true);
    expect(find.text(_tr('cs', 'routeSaveTitle')), findsWidgets);
    expect(_field(tester, 0).controller!.text, 'Pálava za soumraku');
    expect(_field(tester, 1).controller!.text, 'Vinné sklepy');
    await rtEnd(tester);
  });

  testWidgets('prázdný název → hláška; neúspěšné uložení se nepamatuje', (tester) async {
    await _pumpBuilder(tester, RouteBuilderScreen(route: _custom('')));
    await _openSave(tester, true);
    await _fillAndSend(tester, 'routeSaveBtn', '', '');
    expect(find.text(_tr('cs', 'poiSubmitNameReq')), findsOneWidget); // název je povinný
    expect(_writes, isEmpty);
    await _hideSnack(tester);
    await _fillAndSend(tester, 'routeSaveBtn', 'FAIL', 'x');
    expect(find.text(_tr('cs', 'routeSaveErr')), findsOneWidget); // list zůstal otevřený
    await _hideSnack(tester);
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await _frames(tester);
    await _openSuggest(tester, true);
    expect(_field(tester, 0).controller!.text, '');
    await rtEnd(tester);
  });

  testWidgets('uložená trasa z Mých zážitků → list Navrhnout nese její název', (tester) async {
    final r = RouteItem(id: 'custom', name: 'Šumava víkend', routeType: 'poi', waypoints: [_a.latLng!, _b.latLng!]);
    await _pumpBuilder(tester, RouteBuilderScreen(route: r, initialStops: [BuilderStopSpec(_a.latLng!), BuilderStopSpec(_b.latLng!)]));
    await _openSuggest(tester, true);
    expect(_field(tester, 0).controller!.text, 'Šumava víkend');
    await rtEnd(tester);
  });

  // Předvyplněné listy v 8 jazycích × 2 velikostech (žádné nové texty, ale
  // delší předvyplněný obsah nesmí nic přetéct).
  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      for (final suggest in [false, true]) {
        final w = size.width.toInt(), h = size.height.toInt();
        final kind = suggest ? 'suggest' : 'save';
        testWidgets('prefilled $kind sheet $lang ${w}x$h', (tester) async {
          final key = GlobalKey();
          final names = RouteNameMemory(name: 'Šumava víkend přes Kvildu a Modravu', desc: 'Přes Kvildu, Modravu a Horskou Kvildu, zpět údolím Vydry.');
          await pumpV2(tester, Builder(builder: (c) {
            return Center(
              child: TextButton(
                onPressed: () => (suggest ? showRouteSuggestSheet : showRouteSaveSheet)(c,
                    names: names, onSubmit: (_, __) async => true, onDone: () async {}),
                child: const Text('OPEN'),
              ),
            );
          }), lang: lang, size: size, boundaryKey: key);
          await tester.tap(find.text('OPEN'));
          await expectCleanFrames(tester);
          expect(_field(tester, 0).controller!.text, names.name);
          expect(_field(tester, 1).controller!.text, names.desc);
          expect(find.text(_tr(lang, suggest ? 'routeSuggestTitle' : 'routeSaveTitle')), findsOneWidget);
          await maybeShot(tester, key, 'routes__names__${kind}__${lang}__${w}x$h');
        });
      }
    }
  }
}
