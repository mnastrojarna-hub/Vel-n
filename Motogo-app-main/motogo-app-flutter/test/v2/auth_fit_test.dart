// Přihlášení + registrace (sdílené staré obrazovky, oba vzhledy): na 320 dp
// v 8 jazycích, normální i velké písmo (×1.3) nic nepřeteče — „MOTO GO 24“
// se zmenší místo oříznutí, patička se zalomí, jméno / příjmení se při
// nedostatku místa složí pod sebe (r2).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/features/auth/login_screen.dart';
import 'package:motogo_app/features/auth/register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/v2_harness.dart' show kV2Langs, loadMontserrat, v2TestTheme;

Future<void> _pump(WidgetTester tester, Widget screen, String lang, double scale, bool v2) async {
  tester.view.physicalSize = const Size(320, 690) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => screen),
    GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
    GoRoute(path: '/register', builder: (_, __) => const SizedBox()),
  ]);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      locale: Locale(lang),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      ),
    ),
  ));
}

Future<List<String>> _errors(WidgetTester tester, Widget screen, String lang, double scale, bool v2) async {
  final out = <String>[];
  final orig = FlutterError.onError;
  FlutterError.onError = (d) => out.add(d.exceptionAsString().split('\n').first);
  try {
    await _pump(tester, screen, lang, scale, v2);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3)); // staggered reveal (1.6 s) done
  } finally {
    FlutterError.onError = orig;
  }
  return out;
}

void main() {
  setUpAll(loadMontserrat);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final v2 in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('login 320 ×$scale v2=$v2: no overflow in 8 languages', (tester) async {
        final bad = <String>[];
        for (final lang in kV2Langs) {
          final e = await _errors(tester, const LoginScreen(initialEmail: 'jan.novak@zakaznik.cz'), lang, scale, v2);
          bad.addAll(e.map((x) => '$lang: $x'));
        }
        expect(bad, isEmpty);
      });

      testWidgets('register 320 ×$scale v2=$v2: no overflow in 8 languages', (tester) async {
        final bad = <String>[];
        for (final lang in kV2Langs) {
          final e = await _errors(tester, const RegisterScreen(initialEmail: 'jan.novak@zakaznik.cz'), lang, scale, v2);
          bad.addAll(e.map((x) => '$lang: $x'));
        }
        expect(bad, isEmpty);
      });
    }
  }

  testWidgets('register: name fields side by side (cs ×1.0), stacked when the label would be cut (de ×1.3)', (tester) async {
    expect(await _errors(tester, const RegisterScreen(), 'cs', 1.0, false), isEmpty);
    final a = tester.getTopLeft(find.byType(TextField).at(0)), b = tester.getTopLeft(find.byType(TextField).at(1));
    expect(a.dy, b.dy);
    expect(await _errors(tester, const RegisterScreen(), 'de', 1.3, false), isEmpty);
    final c = tester.getTopLeft(find.byType(TextField).at(0)), d = tester.getTopLeft(find.byType(TextField).at(1));
    expect(d.dy, greaterThan(c.dy));
    expect(d.dx, c.dx);
  });
}
