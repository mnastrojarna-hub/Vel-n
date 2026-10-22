// v2 ride pause / trips fit matrix (SPEC §16.2 widget tests + r1 rides
// findings): every new state — recorder phases on every surface, trip
// cards, stages, stats, trip detail, merge, the stop / name / delete
// dialogs — plus the r1 ride detail / history pages, in 8 languages ×
// 320 / 360 / 412 dp × text scale 1.0 / 1.3 through the verifier's own
// inspector (render_inspect.dart): no FlutterError (overflow), no app copy
// split inside a word, cut / ellipsized or clipped, no raw key, no
// fallback-language text. Needs real Montserrat (pub cache or
// MG_FONTS_DIR) — skipped otherwise. MG_FIT_DUMP=1 prints findings.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/widgets/map_tile_errors.dart';
import 'package:motogo_app/features/routes/v2/rides/recorder_parts_v2.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_actions_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_core.dart' show launcher, tapOpen;
import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/fakes_rides.dart';
import '../support/fakes_rides_pause.dart';
import '../support/fakes_routes_http.dart';
import '../support/v2_harness.dart';
import 'rides_cases.dart';
import 'rides_pause_cases.dart';
import 'rides_pause_parts.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];
const _scales = [1.0, 1.3];
final _loc = RegExp(r'(package:motogo_app/[^\s:)]+:\d+|file://[^\s)]+/lib/[^\s:)]+:\d+)');

bool get _realFonts {
  final dir = Platform.environment['MG_FONTS_DIR'];
  return montserratLoaded || (dir != null && dir.isNotEmpty && Directory(dir).existsSync());
}

class _Unit {
  final String name;
  final Widget Function() build;
  final List<Override> Function() overrides;
  final bool page;
  final double? height;
  final Future<void> Function(WidgetTester)? after;
  const _Unit(this.name, this.build, this.overrides, {this.page = false, this.height = 2600, this.after});
}

Widget _frame(double scale, bool page, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: page ? child : SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child)),
      ),
    );

Future<List<String>> _run(WidgetTester t, _Unit u, String lang) async {
  final out = <String>[];
  for (final size in _sizes) {
    for (final scale in _scales) {
      final id = '${u.name} $lang ${size.width.toInt()} ×$scale';
      await t.pumpWidget(const SizedBox());
      MgMotion.resetSession();
      final errors = <(String, String)>[];
      final orig = FlutterError.onError;
      FlutterError.onError = (d) => errors.add((d.exceptionAsString().split('\n').first.trim(), d.toString()));
      try {
        await pumpV2(t, _frame(scale, u.page, u.build()),
            lang: lang, size: Size(size.width, u.height ?? size.height), reducedMotion: true, overrides: u.overrides(), scaffold: !u.page);
        await t.pump(const Duration(milliseconds: 700));
        if (u.after != null) await u.after!(t);
        await t.pump(const Duration(milliseconds: 700));
      } finally {
        FlutterError.onError = orig;
      }
      for (final (first, e) in errors) {
        final loc = _loc.firstMatch(e)?.group(0)?.replaceAll(RegExp(r'^.*?/lib/'), 'lib/') ?? '';
        out.add('$id: exception $first @ $loc');
      }
      final maps = find.byType(FlutterMap, skipOffstage: false).evaluate().map((e) => e.renderObject).whereType<RenderObject>().toSet();
      // The shared bottom nav (shell code) is checked by its own matrix.
      final navs = find.byType(V2NavBar).evaluate().map((e) => e.renderObject).whereType<RenderObject>().toSet();
      for (final f in inspectFrame(t.binding.renderViews.first, lang, size, ignore: maps, nav: navs)) {
        if (f.fail) {
          out.add('$id: ${f.kind} "${f.text}" ${f.detail}');
        } else if (Platform.environment['MG_FIT_ALL'] != null && f.kind != 'czech-text') {
          debugPrint('WARN: $id: ${f.kind} "${f.text}" ${f.detail}');
        }
      }
      await t.pumpWidget(const SizedBox());
      MapTileErrors.retry();
      await t.pump(const Duration(seconds: 6));
    }
  }
  return out;
}

void _expectClean(List<String> found) {
  if (Platform.environment['MG_FIT_DUMP'] != null) {
    for (final f in found) {
      debugPrint('FIT: $f');
    }
  }
  expect(found, isEmpty, reason: found.take(12).join('\n'));
}

Future<void> _tapStop(WidgetTester t) async {
  final f = find.byType(RecorderStopButtonV2);
  if (f.evaluate().isEmpty) return;
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

List<_Unit> _units() {
  final pages = pausePageCases();
  final rec = pauseRecorderCases();
  final detail = detailCases();
  final moje = mojeCases();
  return [
    _Unit('docks', docksPart, tripOverrides),
    _Unit('home-rows', homeRowsPart, tripOverrides),
    _Unit('moje-rows', mojeRowsPart, tripOverrides),
    _Unit('nav-sheet', navAndSheetPart, tripOverrides),
    _Unit('recorder-parts', recorderPartsPart, tripOverrides),
    _Unit('cards', cardsPart, tripOverrides),
    for (final e in rec.entries) _Unit('recorder-${e.key}', e.value.$1, e.value.$2, page: true, height: null),
    for (final e in pages.entries) _Unit('page-${e.key}', e.value.$1, e.value.$2, page: true, height: 3000),
    // r1: ride detail title / captions / sections, history card.
    for (final k in ['motogo', 'private', 'gap'])
      _Unit('r1-detail-$k', detail[k]!.$1, detail[k]!.$2, page: true, height: 2600),
    _Unit('r1-moje-history', moje['history']!.$1, moje['history']!.$2, page: true, height: 2000),
    // Dialogs: stop confirm while paused (r1: no spinner), trip name.
    _Unit('dlg-stop-paused', rec['manual-paused']!.$1, rec['manual-paused']!.$2, page: true, height: null, after: _tapStop),
    _Unit('dlg-trip-name', () => launcher((c) => askTripNameV2(c)), tripOverrides, page: true, height: null, after: tapOpen),
  ];
}

void main() {
  setUpAll(() async {
    await loadRenderFonts();
    registerRidesStrings();
    ridesMockPathProvider();
    HttpOverrides.global = RtFakeHttpOverrides();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  final only = Platform.environment['MG_FIT_ONLY'];
  for (final u in _units()) {
    if (only != null && only.isNotEmpty && !u.name.contains(only)) continue;
    for (final lang in kV2Langs) {
      testWidgets('fit ${u.name} $lang', (tester) async {
        if (!_realFonts) return;
        _expectClean(await _run(tester, u, lang));
      });
    }
  }
}
