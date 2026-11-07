// auth_sos_misc (ASM-31): every v2 view of the package (login, register
// 1–3, reset 1–3, welcome, SOS screens / sheets, scanner) fits 320 / 360 /
// 412 dp in all 8 languages at text scale 1.0 and 1.3 — no overflow, no
// exception (always on; the render matrix adds the inspector checks).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_auth_sos_misc.dart';
import '../render/render_harness.dart' show RenderCase, loadRenderFonts;
import '../support/v2_harness.dart' show kV2Langs, v2TestTheme;

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];

Future<List<String>> _errors(WidgetTester t, RenderCase c, String lang, Size size, double scale) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  final out = <String>[];
  final orig = FlutterError.onError;
  FlutterError.onError = (d) => out.add(d.exceptionAsString().split('\n').first);
  try {
    await t.pumpWidget(ProviderScope(
      overrides: [
        rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
        rankArcPctProvider.overrideWithValue(50),
        ...c.overrides(),
      ],
      child: MaterialApp(
        key: ValueKey('$lang$size$scale${c.id}'),
        locale: Locale(lang),
        supportedLocales: supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: v2TestTheme(),
        builder: (ctx, child) => MgV2Scope(
          enabled: true,
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: child!,
          ),
        ),
        home: c.scaffold ? Scaffold(body: c.build()) : c.build(),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    if (c.after != null) await c.after!(t);
    await t.pump(const Duration(milliseconds: 500));
  } finally {
    FlutterError.onError = orig;
  }
  return out;
}

void main() {
  setUpAll(loadRenderFonts);
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  for (final c in authSosMiscUxCases()) {
    if (c.screen == 'login' && c.state == 'screen') continue; // covered by auth_fit_test (routed screen)
    for (final scale in [1.0, 1.3]) {
      testWidgets('${c.id} ×$scale fits 320/360/412 in 8 languages', (t) async {
        addTearDown(t.view.reset);
        final bad = <String>[];
        for (final lang in kV2Langs) {
          for (final s in _sizes) {
            bad.addAll((await _errors(t, c, lang, s, scale)).map((e) => '$lang ${s.width.toInt()}: $e'));
          }
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 4));
        expect(bad, isEmpty);
      });
    }
  }
}
