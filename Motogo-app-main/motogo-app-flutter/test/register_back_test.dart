// Registrace (první věc nového zákazníka): systémové zpět z nedotčeného
// 1. kroku vede na přihlášení a NEZAVŘE appku; s rozepsanými údaji se nejdřív
// zeptá („Zůstat“ nechá text, „Zahodit“ vede na přihlášení). Jedno stisknutí
// = jeden krok (BackButtonListener + PopScope se nesmí sejít). Oba vzhledy.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/widgets/mg_back.dart';
import 'package:motogo_app/features/auth/register_screen.dart';

import 'v2/support/v2_harness.dart' show v2TestTheme;

String _cs(String k) => translations['cs']![k]!;

/// Same as test/refix_states_test.dart: Android system back (popRoute);
/// true = the app would close (SystemNavigator.pop).
Future<bool> _systemBack(WidgetTester tester) async {
  var closed = false;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') closed = true;
    return null;
  });
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  return closed;
}

Future<GoRouter> _pump(WidgetTester t, {required bool v2, bool pushed = true}) async {
  t.view.physicalSize = const Size(412, 915) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final router = GoRouter(initialLocation: pushed ? '/login' : '/register', routes: [
    GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Center(child: Text('LOGIN')))),
    // As in lib/core/router.dart.
    GoRoute(path: '/register', builder: (_, __) => const MgBackGuard(child: RegisterScreen())),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('cs'),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: v2,
        child: MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: child!),
      ),
    ),
  ));
  await t.pump();
  if (pushed) {
    router.push('/register');
    await t.pumpAndSettle();
  }
  expect(find.byType(RegisterScreen), findsOneWidget);
  return router;
}

void main() {
  for (final v2 in [false, true]) {
    final look = v2 ? 'new look' : 'old look';

    testWidgets('$look: system back on an untouched step 1 → login, app stays open', (t) async {
      await _pump(t, v2: v2);
      final closed = await _systemBack(t);
      expect(closed, isFalse);
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('$look: register as the only page → back goes to login, not out of the app', (t) async {
      await _pump(t, v2: v2, pushed: false);
      final closed = await _systemBack(t);
      expect(closed, isFalse);
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('$look: typed first name → discard confirmation; stay keeps text, discard → login', (t) async {
      await _pump(t, v2: v2);
      await t.enterText(find.byType(TextField).first, 'Jan');
      await t.pump();
      var closed = await _systemBack(t);
      expect(closed, isFalse);
      expect(find.text(_cs('eoDiscardTitle')), findsOneWidget, reason: 'one confirmation, not two');
      await t.tap(find.text(_cs('eoStay')));
      await t.pumpAndSettle();
      expect(find.text(_cs('eoDiscardTitle')), findsNothing);
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.text('Jan'), findsOneWidget);

      closed = await _systemBack(t);
      expect(closed, isFalse);
      expect(find.text(_cs('eoDiscardTitle')), findsOneWidget);
      await t.tap(find.text(_cs('eoDiscard')));
      await t.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('LOGIN'), findsOneWidget);
    });
  }
}
