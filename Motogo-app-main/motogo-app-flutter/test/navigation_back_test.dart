// Navigace zpět (požadavek majitele 2026-10-16): viditelné a trefitelné
// zpět/zavřít, systémové zpět bez historie vede na rodiče (ne zavření appky),
// odkaz s vlastním schématem (návrat ze Stripe 3DS) nic nerozbije.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/safe_router_config.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/core/widgets/mg_back.dart';
import 'package:motogo_app/core/widgets/mg_nav_controls.dart';

const _langs = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'];

Future<void> _platformNav(WidgetTester tester, MethodCall call) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(call),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// Systémové „zpět" (Android tlačítko / gesto). Vrací true, když by se appka
/// zavřela (framework zavolal SystemNavigator.pop).
Future<bool> _systemBack(WidgetTester tester) async {
  var closed = false;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') closed = true;
      return null;
    },
  );
  await _platformNav(tester, const MethodCall('popRoute'));
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
  return closed;
}

GoRouter _router({String initial = '/'}) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/success',
          builder: (_, __) => const MgBackGuard(child: Scaffold(body: Text('SUCCESS'))),
        ),
        ShellRoute(
          builder: (_, __, child) => Scaffold(body: MgBackGuard(shell: true, child: child)),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
            GoRoute(path: '/profile', builder: (_, __) => const Text('PROFILE')),
            GoRoute(path: '/shop', builder: (_, __) => const Text('SHOP')),
            GoRoute(path: '/reservations', builder: (_, __) => const Text('RESERVATIONS')),
          ],
        ),
      ],
    );

void main() {
  group('MgBackTap', () {
    testWidgets('48 px hit area without changing layout + screen-reader label',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Center(
                child: MgBackTap(
                  onTap: () => taps++,
                  child: const SizedBox(width: 36, height: 36),
                ),
              ),
            ),
          ),
        ),
      ));
      // Rozvržení beze změny: pořád 36 × 36.
      expect(tester.getSize(find.byType(MgBackTap)), const Size(36, 36));
      final c = tester.getCenter(find.byType(MgBackTap));
      await tester.tapAt(c);
      expect(taps, 1);
      // 4 px vedle kresleného prvku (hrana 18 px od středu) → pořád zásah.
      await tester.tapAt(c + const Offset(22, 0));
      await tester.tapAt(c + const Offset(0, -22));
      expect(taps, 3);
      // Mimo 48 px → nic.
      await tester.tapAt(c + const Offset(30, 0));
      expect(taps, 3);
      final label = find.bySemanticsLabel(translations['en']!['back']!);
      expect(label, findsOneWidget);
      expect(
        tester.getSemantics(label),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('sheet ✕ closes the bottom sheet', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [MgSheetHandle(), Text('SHEET')],
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsOneWidget);
      await tester.tap(find.byType(MgSheetClose));
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsNothing);
    });

    testWidgets('sheet ✕ respects PopScope (e.g. payment running)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => const PopScope(
                  canPop: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [MgSheetHandle(), Text('SHEET')],
                  ),
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MgSheetClose));
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsOneWidget);
    });
  });

  group('system back without history → parent, never closes the app', () {
    testWidgets('screen reached via go (Menu) → Home; Home closes the app',
        (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/profile');
      await tester.pumpAndSettle();
      expect(find.text('PROFILE'), findsOneWidget);
      expect(await _systemBack(tester), isFalse);
      expect(find.text('HOME'), findsOneWidget);
      // Domů je kořen — tam „zpět" appku zavře (konvence Androidu).
      expect(await _systemBack(tester), isTrue);
    });

    testWidgets('thank-you page outside the shell → Reservations', (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/success');
      await tester.pumpAndSettle();
      expect(find.text('SUCCESS'), findsOneWidget);
      expect(await _systemBack(tester), isFalse);
      expect(find.text('RESERVATIONS'), findsOneWidget);
    });

    testWidgets('pushed screen keeps the normal pop', (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/profile');
      await tester.pumpAndSettle();
      router.push('/shop');
      await tester.pumpAndSettle();
      expect(find.text('SHOP'), findsOneWidget);
      expect(await _systemBack(tester), isFalse);
      expect(find.text('PROFILE'), findsOneWidget);
    });
  });

  group('custom-scheme links (Stripe 3DS return motogo24://payment)', () {
    test('only non-http(s) schemes are foreign', () {
      expect(mgIsForeignSchemeLink(Uri.parse('motogo24://payment?payment_intent=pi_1')), isTrue);
      expect(mgIsForeignSchemeLink(Uri.parse('https://motogo24.cz/app/reservations')), isFalse);
      expect(mgIsForeignSchemeLink(Uri.parse('/reservations/abc')), isFalse);
    });

    testWidgets('warm: the current screen stays (payment is not interrupted)',
        (tester) async {
      final router = _router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: mgSafeRouterConfig(router)));
      router.go('/profile');
      await tester.pumpAndSettle();
      await _platformNav(
        tester,
        const MethodCall('pushRouteInformation',
            {'location': 'motogo24://payment?payment_intent=pi_1', 'state': null}),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('PROFILE'), findsOneWidget);
      // Router dál normálně funguje.
      router.go('/shop');
      await tester.pumpAndSettle();
      expect(find.text('SHOP'), findsOneWidget);
    });

    testWidgets('cold start from the link opens Home',
        (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = 'motogo24://payment?x=1';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final router = _router(initial: '/profile');
      await tester.pumpWidget(MaterialApp.router(routerConfig: mgSafeRouterConfig(router)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('config is cached per router (no re-parse on rebuild)', (tester) async {
      final router = _router();
      expect(identical(mgSafeRouterConfig(router), mgSafeRouterConfig(router)), isTrue);
    });
  });

  group('discard confirmation', () {
    testWidgets('custom title/body, Stay keeps, Discard confirms', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result =
                await confirmDiscard(context, title: 'T-ROUTE', body: 'B-ROUTE'),
            child: const Text('GO'),
          ),
        ),
      ));
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      expect(find.text('T-ROUTE'), findsOneWidget);
      expect(find.text('B-ROUTE'), findsOneWidget);
      await tester.tap(find.text(translations['en']!['eoStay']!));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(translations['en']!['eoDiscard']!));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('navigation texts', () {
    test('every nav* key exists in all 8 languages, non-empty, translated', () {
      final keys = translations['cs']!.keys.where((k) => k.startsWith('nav') &&
          (k.startsWith('navDiscard') || k.startsWith('navDocs')));
      expect(keys.length, greaterThanOrEqualTo(3));
      for (final k in keys) {
        for (final l in _langs) {
          final v = translations[l]?[k];
          expect(v, isNotNull, reason: '$l/$k');
          expect(v!.trim(), isNotEmpty, reason: '$l/$k');
          if (l != 'cs') expect(v, isNot(translations['cs']![k]), reason: '$l/$k');
        }
      }
    });
  });
}
