// FND-1 … FND-4: flag mirror, motion tokens, haptics, page transitions.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/v2/flag/v2_gate.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_haptic.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/motion/mg_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _reduced(Widget child, {bool reduced = true}) =>
    MediaQuery(data: MediaQueryData(disableAnimations: reduced), child: child);

Widget _app({required TargetPlatform platform, required Widget home, bool reduced = false}) => MaterialApp(
      theme: ThemeData(platform: platform, pageTransitionsTheme: MgPageTransitions.theme()),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: home,
    );

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Align(alignment: Alignment.topLeft, child: Text('B'))),
            )),
            child: const Text('A'),
          ),
        ),
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FND-1 MgV2.applied', () {
    for (final on in [true, false]) {
      testWidgets('gate applies $on', (tester) async {
        MgV2.debugSetApplied(!on);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: on)),
          ],
          child: MaterialApp(builder: (c, child) => MgV2Gate(child: child!), home: const SizedBox()),
        ));
        await tester.pump();
        expect(MgV2.applied, on);
      });
    }
  });

  testWidgets('FND-2 sheetStyle: reduced → no animation, else 300 / 250 emphasized', (tester) async {
    late AnimationStyle a, b;
    await tester.pumpWidget(_reduced(Builder(builder: (c) {
      a = MgMotion.sheetStyle(c);
      return const SizedBox();
    })));
    await tester.pumpWidget(_reduced(reduced: false, Builder(builder: (c) {
      b = MgMotion.sheetStyle(c);
      return const SizedBox();
    })));
    expect(a, AnimationStyle.noAnimation);
    expect(b.duration, MgMotion.sheet);
    expect(b.reverseDuration, MgMotion.sheetReverse);
    expect(b.curve, MgMotion.emphasized);
    expect(MgMotion.dialog, const Duration(milliseconds: 180));
    expect(MgMotion.countUp, const Duration(milliseconds: 700));
  });

  testWidgets('FND-3 haptics: select = selectionClick, sos = heavyImpact', (tester) async {
    final log = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    MgHaptic.select();
    MgHaptic.sos();
    expect(log, ['HapticFeedbackType.selectionClick', 'HapticFeedbackType.heavyImpact']);
  });

  group('FND-4 page transitions', () {
    testWidgets('android builder: predictive back, reduced → the page itself', (tester) async {
      final b = MgPageTransitions.theme().builders[TargetPlatform.android]!;
      final route = MaterialPageRoute<void>(builder: (_) => const SizedBox());
      const child = SizedBox(key: Key('page'));
      late Widget normal, reduced;
      await tester.pumpWidget(_reduced(reduced: false, Builder(builder: (c) {
        normal = b.buildTransitions(route, c, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation, child);
        return const SizedBox();
      })));
      await tester.pumpWidget(_reduced(Builder(builder: (c) {
        reduced = b.buildTransitions(route, c, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation, child);
        return const SizedBox();
      })));
      expect(normal.runtimeType.toString(), contains('PredictiveBack'));
      expect(identical(reduced, child), isTrue);
      expect(MgPageTransitions.theme().builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    });

    for (final reduced in [false, true]) {
      testWidgets('android push mid-transition moves the page; reduced=$reduced', (tester) async {
        tester.view.physicalSize = const Size(360, 780) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(platform: TargetPlatform.android, home: const _Home(), reduced: reduced));
        await tester.tap(find.text('A'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final mid = tester.getTopLeft(find.text('B'));
        await tester.pumpAndSettle();
        final end = tester.getTopLeft(find.text('B'));
        expect(mid == end, reduced);
      });
    }

    for (final reduced in [false, true]) {
      testWidgets('iOS left-edge drag pops a pushed page (reduced=$reduced)', (tester) async {
        tester.view.physicalSize = const Size(360, 780) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(platform: TargetPlatform.iOS, home: const _Home(), reduced: reduced));
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        expect(find.text('B'), findsOneWidget);
        final g = await tester.startGesture(const Offset(5, 300));
        for (var i = 0; i < 10; i++) {
          await g.moveBy(const Offset(20, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(find.text('B'), findsNothing);
        expect(find.text('A'), findsOneWidget);
      });
    }

    for (final reduced in [false, true]) {
      testWidgets('mgTabPage fades the incoming tab; reduced=$reduced → none', (tester) async {
        final router = GoRouter(routes: [
          GoRoute(path: '/', pageBuilder: (c, s) => mgTabPage(key: s.pageKey, child: const Text('one'))),
          GoRoute(path: '/two', pageBuilder: (c, s) => mgTabPage(key: s.pageKey, child: const Text('two'))),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          routerConfig: router,
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: reduced), child: child!),
        ));
        router.go('/two');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        final fades = tester
            .widgetList<FadeTransition>(find.ancestor(of: find.text('two'), matching: find.byType(FadeTransition)))
            .where((f) => f.opacity.value < 1);
        expect(fades.isNotEmpty, !reduced);
        await tester.pumpAndSettle();
        expect(find.text('two'), findsOneWidget);
      });
    }
  });
}
