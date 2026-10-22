// fix:routes r1b — the r1 verify:render Trasy findings as an always-on
// matrix: 8 languages × 320 / 360 / 412 dp × text scale 1.0 / 1.3, the
// app's real strings, every frame through the verifier's own inspector
// (render_inspect.dart): no FlutterError (RenderFlex overflow), no word of
// app copy split across lines, no cut / ellipsized app copy, no text wider
// than its box, nothing clipped. Covered (r1_area_issues.json → routes):
//  1. Místa: place-card type line (every category, community, route), ★ +
//     long distance row, filter band chips (every category, uk / de long
//     labels), the location prompt; the list / no-location / picker pages;
//  2. route detail: stat tiles (Délka · Čas · Obtížnost · míst, every
//     difficulty × type × pager), "Místa na trasu" cards (2-line text at
//     ×1.3); the ok / no-POI / hard-abroad pages;
//  3. planner: the page at the PHONE height (nothing overflows — the part
//     between map and dock scrolls) and in a tall view (every text checked):
//     hint, "Přidat z bodů zájmu", nearby POI header + chips, empty text.
// Map markers clipped at a map edge are by design (ignored like in the
// matrix). Findings in shared code reported to its owner (MgSegmented's
// "Recommen|ded") are printed, failing only with MG_STRICT_SHARED=1;
// MG_FIT_DUMP=1 prints every failing finding. The full screens + scroll
// positions stay in the opt-in matrix: `MG_VERIFY_RENDER=1
// [MG_VERIFY_SCALE=1.0] flutter test test/v2/render/render_routes_test.dart`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/widgets/map_tile_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_routes.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'routes_cases.dart' as a;
import 'routes_cases2.dart' as b;
import 'routes_fit_parts.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];
const _scales = [1.0, 1.3];
final _loc = RegExp(r'(package:motogo_app/[^\s:)]+:\d+|file://[^\s)]+/lib/[^\s:)]+:\d+)');

bool get _realFonts {
  final dir = Platform.environment['MG_FONTS_DIR'];
  return montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
}

Widget _frame(double scale, bool page, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: page ? child : SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child)),
      ),
    );

class _Part {
  final String name;
  final Widget Function() build;
  final List<Override> Function() overrides;
  final bool page;

  /// View height (null = the phone's own height).
  final double? height;
  const _Part(this.name, this.build, this.overrides, {this.page = false, this.height = 2600});
}

_Part _page(String name, a.RtCaseT c, {double? height = 3200}) => _Part(name, c.$1, c.$2, page: true, height: height);

Future<List<String>> _matrix(WidgetTester t, _Part p) async {
  final out = <String>[];
  for (final lang in kV2Langs) {
    for (final size in _sizes) {
      for (final scale in _scales) {
        final id = '${p.name} $lang ${size.width.toInt()} ×$scale';
        await t.pumpWidget(const SizedBox());
        MgMotion.resetSession();
        final errors = <(String, String)>[];
        final orig = FlutterError.onError;
        FlutterError.onError = (d) => errors.add((d.exceptionAsString().split('\n').first.trim(), d.toString()));
        try {
          await pumpV2(t, _frame(scale, p.page, p.build()),
              lang: lang, size: Size(size.width, p.height ?? size.height), reducedMotion: true, overrides: p.overrides());
          await t.pump(const Duration(milliseconds: 700));
          await t.pump(const Duration(milliseconds: 700));
        } finally {
          FlutterError.onError = orig;
        }
        for (final (first, e) in errors) {
          final loc = _loc.firstMatch(e)?.group(0)?.replaceAll('package:motogo_app/', 'lib/').replaceAll(RegExp(r'^.*?/lib/'), 'lib/') ?? '';
          out.add('$id: exception $first @ $loc');
        }
        // Map markers at a map edge are clipped by design (also off-screen
        // cached maps → skipOffstage: false).
        final maps = find.byType(FlutterMap, skipOffstage: false).evaluate().map((e) => e.renderObject).whereType<RenderObject>().toSet();
        for (final f in inspectFrame(t.binding.renderViews.first, lang, size, ignore: maps)) {
          if (f.fail) out.add('$id: ${f.kind} "${f.text}" ${f.detail}');
        }
        await t.pumpWidget(const SizedBox());
        MapTileErrors.retry();
        await t.pump(const Duration(seconds: 6));
      }
    }
  }
  return out;
}

/// Shared v2 code reported to its owner, not routes: MgSegmented splits
/// "Recommended" / "Рекомендований" in the planner's profile switch.
const _reported = ['@ lib/core/v2/widgets/mg_segmented.dart:'];

void _expectClean(List<String> found) {
  final strict = Platform.environment['MG_STRICT_SHARED'] != null;
  final other = found.where((f) => _reported.any(f.contains)).toList();
  for (final f in other) {
    debugPrint('shared (reported, not routes): $f');
  }
  final fails = strict ? found : found.where((f) => !other.contains(f)).toList();
  if (Platform.environment['MG_FIT_DUMP'] != null) {
    for (final f in fails) {
      debugPrint('FIT: $f');
    }
  }
  expect(fails, isEmpty, reason: fails.take(12).join('\n'));
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerRoutesStrings();
    mockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1 Místa: place cards, filter chips, location prompt, pages', (tester) async {
    if (!_realFonts) return;
    final places = a.placesCases();
    _expectClean([
      ...await _matrix(tester, _Part('place-cards', () => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: placeCardsPart()), routesOverrides)),
      ...await _matrix(tester, _Part('places-filters', placesFiltersPart, routesOverrides)),
      ...await _matrix(tester, _Part('location-prompt', locationPromptPart, routesOverrides)),
      for (final k in ['list', 'no-location', 'picker']) ...await _matrix(tester, _page('places-$k', places[k]!)),
    ]);
  });

  testWidgets('2 route detail: stat tiles, pager, POI cards, pages', (tester) async {
    if (!_realFonts) return;
    final detail = b.detailCases();
    _expectClean([
      ...await _matrix(tester, _Part('detail-cards', detailCardsPart, routesOverrides)),
      for (final k in ['ok', 'no-pois', 'hard-abroad']) ...await _matrix(tester, _page('detail-$k', detail[k]!)),
    ]);
  });

  testWidgets('3 planner: no overflow at the phone height, every text whole', (tester) async {
    if (!_realFonts) return;
    final builder = b.builderCases();
    _expectClean([
      for (final k in ['route', 'empty']) ...[
        ...await _matrix(tester, _page('builder-$k', builder[k]!, height: null)),
        ...await _matrix(tester, _page('builder-$k-tall', builder[k]!, height: 2400)),
      ],
    ]);
  });
}
