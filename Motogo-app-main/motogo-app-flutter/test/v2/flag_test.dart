// Kill-switch `app_v2_ui` (PLAN §3): row absent / true → ON, false → OFF,
// fetch error → last cached value; a change never lands mid-payment or
// inside a focused flow — only on a tab root (or at the next cold start).
// A tab root is safe only as the ONLY page of the stack and without a query:
// the booking form pushes `/profile?edit=personal` over `/booking`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('preload: no pref → ON; stored false → OFF', () async {
    await AppV2UiNotifier.preload();
    expect(AppV2UiNotifier.bootValue, isTrue);
    SharedPreferences.setMockInitialValues({AppV2UiNotifier.prefKey: false});
    await AppV2UiNotifier.preload();
    expect(AppV2UiNotifier.bootValue, isFalse);
    AppV2UiNotifier.bootValue = true;
  });

  test('remote OFF is stored for the next cold start and waits for a safe moment', () async {
    var paying = false;
    final n = AppV2UiNotifier(
      fetch: () async => false,
      paymentRunning: () => paying,
      autoRefresh: false,
      initial: true,
    );
    await n.refresh();
    expect(n.state, isTrue, reason: 'never switched immediately');
    expect(n.pending, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppV2UiNotifier.prefKey), isFalse);

    expect(n.applyPendingIfSafe('/booking'), isFalse, reason: 'focused flow');
    expect(n.applyPendingIfSafe('/reservations/abc'), isFalse, reason: 'not a tab root');
    paying = true;
    expect(n.applyPendingIfSafe('/'), isFalse, reason: 'payment running');
    paying = false;
    expect(n.applyPendingIfSafe('/profile?edit=personal'), isFalse, reason: 'tab root with a query = opened from a flow');
    expect(n.applyPendingIfSafe('/reservations'), isTrue);
    expect(n.state, isFalse);
    expect(n.pending, isNull);
  });

  test('fetch error / offline (null) keeps the current value', () async {
    final n = AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: false);
    await n.refresh();
    expect(n.state, isFalse);
    expect(n.pending, isNull);
  });

  test('same remote value → nothing pending', () async {
    final n = AppV2UiNotifier(fetch: () async => true, autoRefresh: false, initial: true);
    await n.refresh();
    expect(n.pending, isNull);
    expect(n.applyPendingIfSafe('/'), isFalse);
  });

  test('every tab root is a safe point', () {
    for (final r in kV2TabRoots) {
      final n = AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)..pending = false;
      expect(n.applyPendingIfSafe(r), isTrue, reason: r);
    }
  });

  group('safe point vs. the navigation stack (MgV2Gate)', () {
    /// Shell with the tab roots + `/booking`; pending OFF from the start.
    Future<(GoRouter, ProviderContainer)> pumpGate(WidgetTester tester, String initial) async {
      final router = GoRouter(initialLocation: initial, routes: [
        ShellRoute(builder: (c, s, child) => child, routes: [
          for (final p in ['/', '/booking', '/profile']) GoRoute(path: p, builder: (_, __) => Text(p)),
        ]),
      ]);
      final container = ProviderContainer(overrides: [
        appV2UiProvider.overrideWith(
            (ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)..pending = false),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(useMaterial3: true),
          builder: (c, child) => MgV2Gate(router: router, child: child!),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return (router, container);
    }

    testWidgets('/profile?edit=personal pushed over /booking is NOT a safe point', (tester) async {
      final (router, c) = await pumpGate(tester, '/booking');
      expect(c.read(appV2UiProvider), isTrue, reason: 'inside the booking');
      router.push('/profile?edit=personal');
      await tester.pump();
      await tester.pump();
      expect(find.text('/profile'), findsOneWidget);
      expect(c.read(appV2UiProvider), isTrue, reason: 'still mid-booking');
      expect(c.read(appV2UiProvider.notifier).pending, isFalse);
      router.pop();
      await tester.pump();
      await tester.pump();
      expect(c.read(appV2UiProvider), isTrue, reason: 'back in the booking form');
      router.go('/');
      await tester.pump();
      await tester.pump();
      expect(c.read(appV2UiProvider), isFalse, reason: 'Domů as the only page');
    });

    testWidgets('a plain tab root pushed over another page is NOT a safe point either', (tester) async {
      final (router, c) = await pumpGate(tester, '/booking');
      router.push('/profile');
      await tester.pump();
      await tester.pump();
      expect(c.read(appV2UiProvider), isTrue);
      expect(c.read(appV2UiProvider.notifier).pending, isFalse);
    });

    testWidgets('a tab root reached by go with a query is NOT a safe point', (tester) async {
      final (router, c) = await pumpGate(tester, '/booking');
      router.go('/profile?edit=personal');
      await tester.pump();
      await tester.pump();
      expect(c.read(appV2UiProvider), isTrue);
    });

    testWidgets('plain /profile as the only page IS a safe point', (tester) async {
      final (router, c) = await pumpGate(tester, '/booking');
      router.go('/profile');
      await tester.pump();
      await tester.pump();
      expect(c.read(appV2UiProvider), isFalse);
      expect(c.read(appV2UiProvider.notifier).pending, isNull);
    });

    testWidgets('cold start on a plain tab root still applies at once', (tester) async {
      final (_, c) = await pumpGate(tester, '/profile');
      expect(c.read(appV2UiProvider), isFalse);
    });
  });

  testWidgets('MgV2Scope: no scope = OFF (old UI), V2Switch picks exactly one', (tester) async {
    late bool seen;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (c) {
        seen = MgV2.on(c);
        return const V2Switch(v1: Text('OLD'), v2: Text('NEW'));
      }),
    ));
    expect(seen, isFalse);
    expect(find.text('OLD'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: MgV2Scope(enabled: true, child: V2Switch(v1: Text('OLD'), v2: Text('NEW'))),
    ));
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('OLD'), findsNothing);
  });
}
