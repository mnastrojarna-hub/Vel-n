// verify:render harness: every v2 screen / sub-state pumped like the app
// (v2 scope ON, Montserrat, rank overrides) in every language × phone size
// with LARGE TEXT (MG_VERIFY_SCALE, default 1.3) and REDUCED MOTION. Each
// frame — and every scroll position of each vertical scrollable — is
// inspected (render_inspect.dart); ALL FlutterErrors are collected (not
// just the first). Failing findings fail the test; every finding goes to
// MG_VERIFY_REPORT/<pid>.jsonl and a 1× PNG to MG_VERIFY_DIR.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/chrome/mg_status_strip.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/widgets/mg_nav_controls.dart';
import 'package:motogo_app/core/widgets/state_views.dart' show MgBackArrow;
import 'package:motogo_app/features/routes/v2/route_nav_skin_v2.dart' show NavCircleV2;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/v2_harness.dart' show kV2Langs, loadMontserrat, v2TestTheme;
import 'render_inspect.dart';

const kRenderSizes = [Size(320, 690), Size(360, 780), Size(412, 915)];

String? _env(String k) {
  final v = Platform.environment[k];
  return v == null || v.isEmpty ? null : v;
}

double get renderScale => double.tryParse(_env('MG_VERIFY_SCALE') ?? '') ?? 1.3;
List<String> get renderLangs => _env('MG_VERIFY_LANGS')?.split(',') ?? kV2Langs;
List<Size> get renderSizes =>
    _env('MG_VERIFY_SIZES')?.split(',').map((s) {
      final p = s.split('x');
      return Size(double.parse(p[0]), double.parse(p[1]));
    }).toList() ??
    kRenderSizes;

class RenderCase {
  final String area, screen, state;
  final Widget Function() build;
  final List<Override> Function() overrides;
  final Future<void> Function(WidgetTester)? after;
  final Future<void> Function(WidgetTester)? end;
  final int level;
  final bool scaffold;
  final bool loading;
  final GoRouter Function()? router;
  const RenderCase(this.area, this.screen, this.state, this.build, this.overrides,
      {this.after, this.end, this.level = 3, this.scaffold = true, this.loading = false, this.router});
  String get id => '${area}__${screen}__$state';
}

/// The app language also lives in Riverpod (`localeProvider`): providers
/// that build texts outside the widget tree (booking validation, branch
/// info) must see the same language as `MaterialApp.locale`.
class _FixedLocale extends LocaleNotifier {
  _FixedLocale(String lang) {
    state = Locale(lang);
  }
}

bool _fonts = false;

/// Montserrat 400–900 from MG_FONTS_DIR (the Google Fonts files the app
/// downloads, incl. ExtraBold / Black) or the pub-cache 400–700 set.
Future<void> loadRenderFonts() async {
  if (_fonts) return;
  _fonts = true;
  final dir = _env('MG_FONTS_DIR');
  if (dir == null || !Directory(dir).existsSync()) return loadMontserrat();
  final loader = FontLoader('Montserrat');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    final f = File('$dir/Montserrat-$w.ttf');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
  }
  await loader.load();
}

Widget _app(RenderCase c, String lang, GlobalKey key, {double? scale}) {
  Widget builder(BuildContext context, Widget? child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale ?? renderScale), disableAnimations: true),
          child: child!,
        ),
      );
  const delegates = [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate];
  final app = c.router != null
      ? MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: c.router!(),
          locale: Locale(lang),
          supportedLocales: supportedLocales,
          localizationsDelegates: delegates,
          theme: v2TestTheme(),
          builder: builder)
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(lang),
          supportedLocales: supportedLocales,
          localizationsDelegates: delegates,
          theme: v2TestTheme(),
          builder: builder,
          home: c.scaffold ? Scaffold(backgroundColor: const Color(0xFFF4F7F5), body: c.build()) : c.build(),
        );
  return ProviderScope(
    overrides: [
      localeProvider.overrideWith((ref) => _FixedLocale(lang)),
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(c.level)),
      rankArcPctProvider.overrideWithValue(50),
      ...c.overrides(),
    ],
    child: RepaintBoundary(key: key, child: app),
  );
}

Future<bool> _settle(WidgetTester t) async {
  try {
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    return true;
  } on FlutterError {
    return false;
  }
}

Rect? _rectOf(WidgetTester t, Element e) {
  final ro = e.renderObject;
  return ro == null ? null : paintedRect(t.binding.renderViews.first, ro);
}

/// FAB rect (when painted) + the zones it must never cover.
(Rect?, List<Rect>) _fabZones(WidgetTester t) {
  final discs = find.descendant(of: find.byType(MgAiFab), matching: find.byType(MgAiDisc)).evaluate();
  if (discs.isEmpty) return (null, const []);
  final fab = _rectOf(t, discs.first);
  if (fab == null) return (null, const []);
  final zones = <Rect>[];
  for (final e in find.byType(MgFabAvoid).evaluate()) {
    if ((e.widget as MgFabAvoid).kind == MgAvoidKind.tap) continue;
    final r = _rectOf(t, e);
    if (r != null) zones.add(r);
  }
  for (final type in [V2NavBar, MgStatusStrip, MgDock]) {
    for (final e in find.byType(type).evaluate()) {
      final r = _rectOf(t, e);
      if (r != null) zones.add(r);
    }
  }
  return (fab, zones);
}

List<RFinding> _inspect(WidgetTester t, String lang, Size size, {bool first = false}) {
  final (fab, zones) = _fabZones(t);
  // Map markers at the map edge are clipped by design.
  final maps = find.byType(FlutterMap).evaluate().map((e) => e.renderObject).whereType<RenderObject>().toSet();
  final navs = find.byType(V2NavBar).evaluate().map((e) => e.renderObject).whereType<RenderObject>().toSet();
  final out = inspectFrame(t.binding.renderViews.first, lang, size, fab: fab, avoid: zones, ignore: maps, nav: navs);
  if (first && _env('MG_VERIFY_BACKCHECK') != null) {
    // Every screen / sheet needs a visible back or close control (tab roots
    // are filtered out when the report is read).
    var any = false;
    for (final ty in [MgV2Back, MgBackTap, MgSheetClose, MgBackArrow, BackButton, CloseButton, NavCircleV2]) {
      for (final e in find.byType(ty).evaluate()) {
        final r = _rectOf(t, e);
        if (r != null && r.width > 8 && r.height > 8 && r.overlaps(Offset.zero & size)) any = true;
      }
    }
    if (!any) out.add(const RFinding('no-back', false, 'no visible back / close control'));
  }
  if (fab != null) {
    for (final z in zones) {
      if (z.overlaps(fab.deflate(4))) out.add(RFinding('fab-covers', true, 'zone [${z.left.round()},${z.top.round()} ${z.width.round()}x${z.height.round()}]'));
    }
  }
  return out;
}

/// Steps every vertical scrollable through its extent, inspecting each stop.
Future<List<RFinding>> _scrollInspect(WidgetTester t, String lang, Size size, [GlobalKey? key, String? name]) async {
  final out = <RFinding>[];
  var budget = 16;
  final states = find.byType(Scrollable).evaluate().map((e) => (e as StatefulElement).state).whereType<ScrollableState>().toList();
  for (final s in states) {
    if (!s.mounted || axisDirectionToAxis(s.axisDirection) != Axis.vertical) continue;
    final p = s.position;
    if (!p.hasContentDimensions || p.maxScrollExtent < 8 || p.viewportDimension < 150) continue;
    final step = p.viewportDimension * 0.8;
    for (var o = step; budget > 0; o += step) {
      final target = o.clamp(0.0, p.maxScrollExtent);
      p.jumpTo(target);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      // Scroll idle (120 ms) re-evaluates the AI button in a post-frame
      // callback → one more frame shows its settled place.
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 300));
      out.addAll(_inspect(t, lang, size));
      if (key != null && name != null && _env('MG_VERIFY_SCROLLSHOTS') != null) await _shot(t, key, '${name}__s${16 - budget}');
      budget--;
      if (target >= p.maxScrollExtent || !s.mounted) break;
    }
    if (s.mounted) p.jumpTo(0);
  }
  await t.pump();
  return out;
}

Future<void> _shot(WidgetTester t, GlobalKey key, String name) async {
  final dir = _env('MG_VERIFY_DIR');
  if (dir == null) return;
  await t.runAsync(() async {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    final ui.Image img = await ro.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return;
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data.buffer.asUint8List());
  });
}

void _report(RenderCase c, String lang, Size size, List<RFinding> fs) {
  final dir = _env('MG_VERIFY_REPORT');
  if (dir == null || fs.isEmpty) return;
  Directory(dir).createSync(recursive: true);
  final f = File('$dir/r_$pid.jsonl');
  final b = StringBuffer();
  for (final x in fs) {
    b.writeln(jsonEncode({
      'area': c.area, 'screen': c.screen, 'state': c.state, 'lang': lang,
      'size': '${size.width.toInt()}x${size.height.toInt()}', 'scale': renderScale, ...x.toJson(),
    }));
  }
  f.writeAsStringSync(b.toString(), mode: FileMode.append, flush: true);
}

final _loc = RegExp(r'(package:motogo_app/[^\s:)]+:\d+:\d+|file://[^\s)]+/lib/[^\s:)]+:\d+:\d+)');

/// [all] = the details rendered WHEN reported (the render object is still
/// attached then, so the creator chain of a lazily built row is known).
RFinding _fromError((FlutterErrorDetails, String) e) {
  final (d, all) = e;
  final first = d.exceptionAsString().split('\n').first.trim();
  final locs = _loc.allMatches(all).map((m) => m.group(0)!.replaceAll(RegExp(r'^.*?/lib/'), 'lib/')).toSet().take(3).join(' ; ');
  final kind = first.contains('overflowed') ? 'overflow' : 'exception';
  final creator = RegExp(r'creator: ([^\n]+)').firstMatch(all)?.group(1) ?? '';
  final chain = creator.length > 260 ? '${creator.substring(0, 260)}…' : creator;
  final cause = RegExp(r'error-causing widget was:\s*\n\s*([^\n]+)').firstMatch(all)?.group(1)?.trim() ?? '';
  return RFinding(kind, true, first, [locs, if (locs.isEmpty) cause, chain].where((x) => x.isNotEmpty).join(' | '));
}

/// The matrix is heavy (~6 700 tests) → opt-in: MG_VERIFY_RENDER=1.
bool get renderEnabled => _env('MG_VERIFY_RENDER') != null;

/// Always-on smoke subset (runs in the default `flutter test` too): key
/// screens at the narrowest phone in cs / de / uk at the app's text scale
/// (main.dart forces no system scaling) — a render regression there fails
/// CI without the opt-in matrix. The full matrix stays the 4.2.0 release
/// gate: `MG_VERIFY_RENDER=1 flutter test test/v2/render/` (+ MG_VERIFY_SCALE=1.0).
const kRenderSmokeCases = {
  'reservations__list__all',
  'shell__tab__routes',
  'rides__moje__rides',
  'profile__loyalty__rank17',
};
const kRenderSmokeLangs = ['cs', 'de', 'uk'];

/// Real Montserrat metrics are needed (MG_FONTS_DIR or the pub-cache
/// gallery fonts); with the test font every word is wider → skip, not fail.
bool get _renderFontsAvailable {
  final dir = _env('MG_FONTS_DIR');
  if (dir != null && Directory(dir).existsSync()) return true;
  final home = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME'] ?? ''}/.pub-cache';
  return Directory('$home/hosted/pub.dev/flutter_gallery_assets-1.0.2/lib/fonts/google_fonts').existsSync();
}

/// One test per case × language × size; reduced motion + large text.
void renderMatrix(List<RenderCase> cases, {Future<void> Function()? setUpAllExtra}) {
  setUpAll(() async {
    await loadRenderFonts();
    if (setUpAllExtra != null) await setUpAllExtra();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  for (final c in cases) {
    for (final lang in renderLangs) {
      for (final size in renderSizes) {
        final w = size.width.toInt(), h = size.height.toInt();
        testWidgets('${c.id} $lang ${w}x$h', skip: !renderEnabled, (tester) => _runCase(tester, c, lang, size));
      }
    }
    if (!renderEnabled && kRenderSmokeCases.contains(c.id)) {
      for (final lang in kRenderSmokeLangs) {
        testWidgets('smoke ${c.id} $lang 320x690', skip: !_renderFontsAvailable,
            (tester) => _runCase(tester, c, lang, const Size(320, 690), scale: 1.0));
      }
    }
  }
}

Future<void> _runCase(WidgetTester tester, RenderCase c, String lang, Size size, {double? scale}) async {
  final w = size.width.toInt(), h = size.height.toInt();
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  final errors = <(FlutterErrorDetails, String)>[];
  final orig = FlutterError.onError;
  FlutterError.onError = (d) => errors.add((d, d.toString()));
  final fs = <RFinding>[];
  try {
    await tester.pumpWidget(_app(c, lang, key, scale: scale));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    if (c.after != null) await c.after!(tester);
    final settled = await _settle(tester);
    if (!settled && !c.loading) fs.add(const RFinding('no-settle', false, 'reduced motion: frame never settles'));
    await tester.pump(const Duration(milliseconds: 400));
    fs.addAll(_inspect(tester, lang, size, first: true));
    await _shot(tester, key, '${c.id}__${lang}__${w}x$h');
    fs.addAll(await _scrollInspect(tester, lang, size, key, '${c.id}__${lang}__${w}x$h'));
    await tester.pump(const Duration(seconds: 3));
    if (c.end != null) await c.end!(tester);
  } finally {
    FlutterError.onError = orig;
  }
  fs.addAll(errors.map(_fromError));
  final full = _env('MG_VERIFY_FULLERR');
  if (full != null && errors.isNotEmpty) {
    Directory(full).createSync(recursive: true);
    File('$full/${c.id}__${lang}__${w}x$h.txt').writeAsStringSync(errors.map((e) => e.$2).join('\n\n======\n\n'));
  }
  final seen = <String>{};
  final uniq = [for (final f in fs) if (seen.add(f.key)) f];
  _report(c, lang, size, uniq);
  final fails = uniq.where((f) => f.fail).map((f) => '${f.kind}: ${f.text} (${f.detail})').toList();
  expect(fails, isEmpty, reason: '${c.id} $lang ${w}x$h');
}
