// Shared harness for the v2 UI tests (PLAN §5.1): pumps a widget in a given
// language / phone size with the v2 scope ON, real Montserrat (when the
// font is in the pub cache), rank overrides and optional reduced motion;
// optional PNG shots for human review (MG_SHOTS_DIR).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/theme.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/tokens/mg_theme_v2.dart';

const kV2Langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
const kV2Sizes = [Size(360, 780), Size(412, 915)];

bool _fontsTried = false;
bool montserratLoaded = false;

/// Loads Montserrat (Regular / Medium / SemiBold / Bold) from the
/// `flutter_gallery_assets` package in the pub cache, so text widths in
/// tests are real. Without it the test font draws 1 em boxes.
Future<void> loadMontserrat() async {
  if (_fontsTried) return;
  _fontsTried = true;
  final home = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME'] ?? ''}/.pub-cache';
  final dir = Directory('$home/hosted/pub.dev/flutter_gallery_assets-1.0.2/lib/fonts/google_fonts');
  if (!dir.existsSync()) return;
  final loader = FontLoader('Montserrat');
  var n = 0;
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final f = File('${dir.path}/Montserrat-$w.ttf');
    if (!f.existsSync()) continue;
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    n++;
  }
  if (n == 0) return;
  await loader.load();
  montserratLoaded = true;
}

final Map<TargetPlatform, ThemeData> _appBase = {};

/// The app's own base theme (`MotoGoTheme.dark`, as main.dart gives it to
/// `MgV2Gate`) with its text themes on the Montserrat family the tests
/// load. GoogleFonts never fetches in tests (no network): runtime fetching
/// is off, its "unable to load" errors / messages stay in this zone (the
/// text themes are re-pointed to Montserrat anyway). Built once per target
/// platform (ThemeData takes `defaultTargetPlatform` when created — iOS
/// tests override it).
ThemeData _appBaseTheme() => _appBase[defaultTargetPlatform] ??= runZonedGuarded<ThemeData>(
      () {
        GoogleFonts.config.allowRuntimeFetching = false;
        final t = MotoGoTheme.dark;
        return t.copyWith(
          textTheme: t.textTheme.apply(fontFamily: 'Montserrat'),
          primaryTextTheme: t.primaryTextTheme.apply(fontFamily: 'Montserrat'),
        );
      },
      (_, __) {},
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    )!;

/// The app's theme in the tests: `MgThemeV2.overlay(MotoGoTheme.dark)` —
/// exactly what the phone shows with the flag ON (v2_gate.dart), so any
/// leftover Material widget renders as on the phone — on Montserrat.
ThemeData v2TestTheme() => MgThemeV2.overlay(_appBaseTheme());

/// The former plain reference theme (M3 light + Montserrat + v2 overlay).
/// NOT the phone's look: only for the flag-OFF old-screen regression guards
/// that were measured against it (`pumpV2(v2: false)`, auth fit, old payment
/// screen) — the old screens stay unchanged, so their guards keep their
/// reference. Judge looks with [v2TestTheme].
ThemeData legacyTestTheme() => MgThemeV2.overlay(ThemeData(
      fontFamily: 'Montserrat',
      useMaterial3: true,
      textTheme: ThemeData(fontFamily: 'Montserrat').textTheme,
    ));

/// Pumps [child] like the app would show it.
Future<void> pumpV2(
  WidgetTester tester,
  Widget child, {
  String lang = 'cs',
  Size size = const Size(360, 780),
  double dpr = 2,
  List<Override> overrides = const [],
  bool reducedMotion = false,
  RankTokens? rank,
  double? arcPct = 50,
  bool v2 = true,
  bool scaffold = true,
  GlobalKey? boundaryKey,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(rank ?? RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(arcPct),
      ...overrides,
    ],
    child: RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Flag OFF = the old screens' guards keep their reference theme.
        theme: v2 ? v2TestTheme() : legacyTestTheme(),
        builder: (context, c) => MgV2Scope(
          enabled: v2,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
              disableAnimations: reducedMotion,
            ),
            child: c!,
          ),
        ),
        home: scaffold ? Scaffold(backgroundColor: const Color(0xFFF4F7F5), body: child) : child,
      ),
    ),
  ));
}

/// Pumps a few frames (animations started, no settle — loops never settle)
/// and fails on any exception / overflow.
Future<void> expectCleanFrames(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  expect(tester.takeException(), isNull);
  await tester.pump(const Duration(seconds: 2));
  expect(tester.takeException(), isNull);
}

/// Writes a PNG of the pumped frame when `MG_SHOTS_DIR` is set (review
/// artefact, not a golden). [boundaryKey] must be the one given to pumpV2.
Future<void> maybeShot(WidgetTester tester, GlobalKey boundaryKey, String name) async {
  final dir = Platform.environment['MG_SHOTS_DIR'];
  if (dir == null || dir.isEmpty) return;
  final langs = Platform.environment['MG_SHOTS_LANGS'];
  if (langs != null && langs.isNotEmpty && !langs.split(',').any((l) => name.contains('__${l}__'))) return;
  await tester.runAsync(() async {
    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    final ui.Image img = await ro.toImage(pixelRatio: tester.view.devicePixelRatio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data.buffer.asUint8List());
  });
}
