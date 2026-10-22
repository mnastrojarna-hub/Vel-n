// Doplnění chybových stavů a navigace zpět po ověření (2026-10-16):
// značka platby per pokus (žádné „nic nestrženo" podle cizího intentu),
// texty fx* v 8 jazycích, pushOrGo mimo AppShell, zpět z onboardingu.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_40_refix_a.dart';
import 'package:motogo_app/core/payment_pending_marker.dart';
import 'package:motogo_app/core/router.dart' show MotoGoBackNav;
import 'package:motogo_app/core/widgets/mg_back.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];
const _key = 'mg_payment_submitted_v2';

Future<bool> _systemBack(WidgetTester tester) async {
  var closed = false;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') closed = true;
      return null;
    },
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  return closed;
}

void main() {
  group('PaymentPendingMarker per attempt', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('new attempt drops the intent of an abandoned attempt', () async {
      // Pokus A: kartový sheet odeslán (intent A), pak zavřen bez zaplacení.
      await PaymentPendingMarker.set('b1', clientSecret: 'cs_A', fresh: true);
      expect((await PaymentPendingMarker.get('b1'))!.clientSecretCurrent, isTrue);
      // Pokus B: stržení uložené karty — intent A už nesmí rozhodovat.
      await PaymentPendingMarker.set('b1', fresh: true);
      await PaymentPendingMarker.set('b1'); // ověřování bez intentu
      final m = await PaymentPendingMarker.get('b1');
      expect(m, isNotNull);
      expect(m!.clientSecret, isNull);
    });

    test('intent recorded in the same attempt stays current', () async {
      await PaymentPendingMarker.set('b2', fresh: true);
      await PaymentPendingMarker.set('b2', clientSecret: 'cs_3ds');
      await PaymentPendingMarker.set('b2');
      final m = await PaymentPendingMarker.get('b2');
      expect(m!.clientSecret, 'cs_3ds');
      expect(m.clientSecretCurrent, isTrue);
    });

    test('legacy marker without attempt id is never treated as current', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({'b3': {'at': now, 'cs': 'cs_old'}}),
      });
      final m = await PaymentPendingMarker.get('b3');
      expect(m!.clientSecretCurrent, isFalse);
    });

    test('expired marker keeps the last intent for the FAB check only', () async {
      final old = DateTime.now()
          .subtract(const Duration(minutes: 20))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode({
          'b4': {'at': old, 'att': old, 'cs': 'cs_4', 'csAtt': old},
        }),
      });
      expect(await PaymentPendingMarker.isPending('b4'), isFalse);
      expect(await PaymentPendingMarker.pendingIds(), isEmpty);
      expect(await PaymentPendingMarker.expiredIntent('b4'), 'cs_4');
      // Obnovení (FAB ověřil, že platba běží) → zase čerstvá značka.
      await PaymentPendingMarker.set('b4');
      expect(await PaymentPendingMarker.isPending('b4'), isTrue);
    });
  });

  test('every fx* text exists in all 8 languages', () {
    final keys = translationsExt40RefixA['cs']!.keys;
    expect(keys, isNotEmpty);
    for (final lang in _langs) {
      for (final k in keys) {
        final v = translations[lang]?[k];
        expect(v, isNotNull, reason: '$lang/$k');
        expect(v!.trim(), isNotEmpty, reason: '$lang/$k');
      }
    }
    // Čeština tyká.
    for (final k in keys) {
      expect(translations['cs']![k], isNot(matches(RegExp(r'\b(Zkuste|Vyberte|Zkontrolujte|vám|Vaše)\b'))));
    }
  });

  testWidgets('pushOrGo from a screen outside the shell opens the target and back works',
      (tester) async {
    final r = GoRouter(
      initialLocation: '/routes',
      routes: [
        GoRoute(
          path: '/my-experiences',
          builder: (_, __) => MgBackGuard(
            child: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => ctx.pushOrGo('/routes/abc'),
                  child: const Text('MYEXP'),
                ),
              ),
            ),
          ),
        ),
        ShellRoute(
          builder: (_, __, child) => Scaffold(body: MgBackGuard(shell: true, child: child)),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
            GoRoute(path: '/routes', builder: (_, __) => const Text('ROUTES')),
            GoRoute(path: '/routes-list', builder: (_, __) => const Text('LIST')),
            GoRoute(path: '/routes/:id', builder: (_, s) => Text('ROUTE ${s.pathParameters['id']}')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: r));
    await tester.pumpAndSettle();
    r.push('/my-experiences');
    await tester.pumpAndSettle();
    await tester.tap(find.text('MYEXP'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ROUTE abc'), findsOneWidget);
    final closed = await _systemBack(tester);
    expect(closed, isFalse);
    expect(find.text('LIST'), findsOneWidget);
  });

  testWidgets('MgOverlayBack takes system back when nothing below can pop', (tester) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Stack(children: [
        const Scaffold(body: Text('LOGIN')),
        MgOverlayBack(
          onBack: () {
            backs++;
            return true;
          },
          child: const SizedBox.expand(),
        ),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    final closed = await _systemBack(tester);
    expect(closed, isFalse);
    expect(backs, 1);
    // Vrstva pryč → zpět se chová jako dřív (appka se zavře).
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('LOGIN'))));
    expect(await _systemBack(tester), isTrue);
  });
}
