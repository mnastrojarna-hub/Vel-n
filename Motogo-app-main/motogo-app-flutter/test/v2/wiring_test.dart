// Gate A wiring (PLAN §1 / §3): the router picks the v2 screens and
// shell only through `V2Switch` (same paths, deep links and back in both
// modes), `MgV2Gate` turns the kill-switch into `MgV2Scope` + theme
// overlay, and the shared foundation fixes made during integration
// (MgPage overlap paint order, solid MgDock, stable MgReveal,
// reduced-motion-safe MgAnimatedSize, cancellable one-shot delays).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/app_shell.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/router.dart';
import 'package:motogo_app/core/v2/chrome/mg_dock.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/core/v2/motion/mg_animated_size.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/catalog/moto_search_screen.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/home/home_screen.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/loyalty/loyalty_ranks_screen.dart';
import 'package:motogo_app/features/loyalty/v2/loyalty_screen_v2.dart';
import 'package:motogo_app/features/profile/profile_screen.dart';
import 'package:motogo_app/features/reservations/reservations_screen.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import 'support/v2_harness.dart';

GoRouterState _state(GoRouter r, String path) => GoRouterState(
      r.configuration,
      uri: Uri.parse(path),
      matchedLocation: path,
      fullPath: path,
      pathParameters: const {},
      pageKey: ValueKey(path),
    );

void main() {
  group('router wiring', () {
    late ProviderContainer container;
    late GoRouter router;
    late ShellRoute shell;

    setUp(() {
      container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream<Session?>.empty()),
      ]);
      router = container.read(routerProvider);
      shell = router.configuration.routes.whereType<ShellRoute>().single;
    });
    tearDown(() => container.dispose());

    GoRoute route(String p) => shell.routes.whereType<GoRoute>().firstWhere((r) => r.path == p);

    Widget pageChild(BuildContext c, String p) {
      final r = route(p);
      if (r.pageBuilder != null) return (r.pageBuilder!(c, _state(router, p)) as NoTransitionPage).child;
      return r.builder!(c, _state(router, p));
    }

    testWidgets('shell + tab roots go through V2Switch, other routes unchanged', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));

      final s = shell.builder!(ctx, _state(router, '/'), const SizedBox()) as V2Switch;
      expect(s.v1, isA<AppShell>());
      expect(s.v2, isA<AppShellV2>());

      void expectSwitch<A, B>(String p) {
        final w = pageChild(ctx, p);
        expect(w, isA<V2Switch>(), reason: p);
        expect((w as V2Switch).v1, isA<A>(), reason: p);
        expect(w.v2, isA<B>(), reason: p);
      }

      expectSwitch<HomeScreen, HomeScreenV2>('/');
      expectSwitch<MotoSearchScreen, MotorkyScreenV2>('/search');
      expectSwitch<ReservationsScreen, ReservationsScreenV2>('/reservations');
      expectSwitch<LoyaltyRanksScreen, LoyaltyScreenV2>('/loyalty');
      // Screens that switch inside themselves keep their route builder.
      expect(pageChild(ctx, '/profile'), isA<ProfileScreen>());
    });

    test('every v2 tab root is a route of the shell (same paths both modes)', () {
      final paths = shell.routes.whereType<GoRoute>().map((r) => r.path).toSet();
      for (final p in kV2TabRoots) {
        expect(paths, contains(p));
      }
      // Paths the old UI already had are all still there.
      for (final p in ['/moto/:id', '/booking', '/payment', '/reservations/:id', '/reservations/:id/edit',
        '/messages', '/messages/:id', '/invoices', '/contracts', '/pobocky', '/pobocky/:index', '/shop',
        '/sos', '/ai-agent', '/permissions', '/loyalty', '/routes-list', '/places-map', '/routes-map', '/routes/:id']) {
        expect(paths, contains(p), reason: p);
      }
    });
  });

  group('MgV2Gate (kill-switch)', () {
    Future<ProviderContainer> pumpGate(WidgetTester tester, bool initial) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        appV2UiProvider.overrideWith(
            (ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: initial)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          builder: (c, child) => MgV2Gate(child: child!),
          home: const V2Switch(v1: Text('OLD UI'), v2: Text('NEW UI')),
        ),
      ));
      return container;
    }

    testWidgets('ON = v2 scope + overlay theme', (tester) async {
      await pumpGate(tester, true);
      expect(find.text('NEW UI'), findsOneWidget);
      final ctx = tester.element(find.text('NEW UI'));
      expect(MgV2.peek(ctx), isTrue);
      expect(Theme.of(ctx).snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    testWidgets('OFF = old UI, app theme untouched', (tester) async {
      await pumpGate(tester, false);
      expect(find.text('OLD UI'), findsOneWidget);
      final ctx = tester.element(find.text('OLD UI'));
      expect(MgV2.peek(ctx), isFalse);
      expect(Theme.of(ctx).snackBarTheme.behavior, isNull);
    });

    testWidgets('pending OFF applies only at a safe tab root', (tester) async {
      final c = await pumpGate(tester, true);
      final n = c.read(appV2UiProvider.notifier);
      n.pending = false;
      expect(n.applyPendingIfSafe('/booking'), isFalse);
      await tester.pump();
      expect(find.text('NEW UI'), findsOneWidget);
      expect(n.applyPendingIfSafe('/reservations'), isTrue);
      await tester.pump();
      expect(find.text('OLD UI'), findsOneWidget);
    });
  });

  group('foundation fixes', () {
    testWidgets('MgPage: the overlapping sheet paints and taps above the header', (tester) async {
      var sheetTaps = 0;
      var headerTaps = 0;
      await pumpV2(
        tester,
        MgPage(
          header: GestureDetector(
            onTap: () => headerTaps++,
            child: Container(key: const ValueKey('hdr'), height: 200, color: const Color(0xFF000000)),
          ),
          sections: [
            GestureDetector(
              onTap: () => sheetTaps++,
              child: Container(key: const ValueKey('sheet'), height: 120, color: const Color(0xFFFFFFFF)),
            ),
          ],
        ),
      );
      await tester.pump();
      final top = tester.getTopLeft(find.byKey(const ValueKey('sheet'))).dy;
      expect(top, closeTo(200 - 24, 0.01));
      // Inside the 24 px overlap → the sheet, not the header.
      await tester.tapAt(const Offset(100, 190));
      expect(sheetTaps, 1);
      expect(headerTaps, 0);
      await tester.tapAt(const Offset(100, 100));
      expect(headerTaps, 1);
    });

    testWidgets('MgPage without overlap keeps header and sections separate', (tester) async {
      await pumpV2(
        tester,
        MgPage(
          overlapHero: false,
          header: const SizedBox(key: ValueKey('hdr'), height: 120),
          sections: const [SizedBox(key: ValueKey('sec'), height: 60)],
        ),
      );
      expect(tester.getTopLeft(find.byKey(const ValueKey('sec'))).dy, closeTo(120, 0.01));
    });

    testWidgets('MgDock (dark) is solid — the page never shows through', (tester) async {
      await pumpV2(tester, const Align(alignment: Alignment.bottomCenter, child: MgDock(child: SizedBox(height: 56))));
      final boxes = tester.widgetList<Container>(find.descendant(of: find.byType(MgDock), matching: find.byType(Container)));
      final deco = boxes.map((c) => c.decoration).whereType<BoxDecoration>().first;
      expect(deco.color, MgColors.night);
      expect(deco.color!.a, 1.0);
    });

    testWidgets('MgReveal(sessionKey) keeps its child mounted across rebuilds', (tester) async {
      MgMotion.resetSession();
      _Probe.inits = 0;
      late StateSetter rebuild;
      var n = 0;
      await pumpV2(tester, StatefulBuilder(builder: (c, set) {
        rebuild = set;
        return MgReveal(sessionKey: 'it', child: _Probe(label: 'n$n'));
      }));
      await tester.pump(const Duration(seconds: 1));
      expect(_Probe.inits, 1);
      rebuild(() => n++);
      await tester.pump();
      expect(find.text('n1'), findsOneWidget);
      expect(_Probe.inits, 1, reason: 'child state must survive the rebuild');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('MgReveal with a delay leaves no pending timer when disposed early', (tester) async {
      MgMotion.resetSession();
      await pumpV2(tester, const MgReveal(index: 5, child: Text('late')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      // No "A Timer is still pending" failure at the end of the test.
    });

    for (final reduced in [false, true]) {
      testWidgets('MgAnimatedSize toggles without layout errors (reduced=$reduced)', (tester) async {
        late StateSetter set;
        var open = false;
        await pumpV2(
          tester,
          StatefulBuilder(builder: (c, s) {
            set = s;
            return Column(children: [
              MgAnimatedSize(
                duration: const Duration(milliseconds: 300),
                alignment: Alignment.topCenter,
                child: open ? const SizedBox(height: 120, width: double.infinity) : const SizedBox(width: double.infinity),
              ),
            ]);
          }),
          reducedMotion: reduced,
        );
        set(() => open = true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        set(() => open = false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _Probe extends StatefulWidget {
  static int inits = 0;
  final String label;
  const _Probe({required this.label});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}
