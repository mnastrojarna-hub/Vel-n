// FND-8: segment swipe, directional switcher, step fade, iOS edge back,
// snap physics, segmented drag thumb / counts, filter chip tab style.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/gestures/mg_edge_back.dart';
import 'package:motogo_app/core/v2/gestures/mg_snap_physics.dart';
import 'package:motogo_app/core/v2/gestures/mg_swipe.dart';
import 'package:motogo_app/core/v2/gestures/mg_swipe_switcher.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_segmented.dart';

import '../support/v2_harness.dart';

const _values = ['a', 'b', 'c'];

Widget _segments({required ValueNotifier<String> v, Widget? inner, ValueNotifier<double>? progress}) =>
    ValueListenableBuilder<String>(
      valueListenable: v,
      builder: (_, value, __) => MgSwipeSegments<String>(
        values: _values,
        value: value,
        progress: progress,
        onChanged: (n) => v.value = n,
        child: inner ?? ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 40, child: Text('$value $i'))]),
      ),
    );

double _shift(WidgetTester tester) => tester
    .widget<Transform>(find.descendant(of: find.byType(MgSwipeSegments<String>), matching: find.byType(Transform)).first)
    .transform
    .getTranslation()
    .x;

void main() {
  group('MgSwipeSegments', () {
    testWidgets('fling ← = next value + selectionClick', (tester) async {
      final log = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') log.add('${c.arguments}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final v = ValueNotifier('a');
      await pumpV2(tester, _segments(v: v));
      await tester.fling(find.text('a 3'), const Offset(-200, 0), 900);
      await tester.pumpAndSettle();
      expect(v.value, 'b');
      expect(log, contains('HapticFeedbackType.selectionClick'));
      await tester.fling(find.text('b 3'), const Offset(200, 0), 900);
      await tester.pumpAndSettle();
      expect(v.value, 'a');
      await tester.fling(find.text('a 3'), const Offset(200, 0), 900);
      await tester.pumpAndSettle();
      expect(v.value, 'a', reason: 'no neighbour on the left');
    });

    testWidgets('slow drag 40 springs back, offset 0', (tester) async {
      final v = ValueNotifier('a');
      await pumpV2(tester, _segments(v: v));
      final g = await tester.startGesture(tester.getCenter(find.text('a 3')));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(_shift(tester), lessThan(0));
      await g.up();
      await tester.pumpAndSettle();
      expect(v.value, 'a');
      expect(_shift(tester), 0);
    });

    testWidgets('vertical drag scrolls the list and never switches', (tester) async {
      final v = ValueNotifier('a');
      await pumpV2(tester, _segments(v: v));
      await tester.fling(find.text('a 5'), const Offset(-30, -300), 1200);
      await tester.pumpAndSettle();
      expect(v.value, 'a');
      expect(find.text('a 0'), findsNothing);
    });

    testWidgets('an inner horizontal list keeps its own drags', (tester) async {
      final v = ValueNotifier('a');
      final inner = Column(children: [
        SizedBox(
          height: 60,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < 20; i++) SizedBox(width: 80, child: Text('chip $i')),
          ]),
        ),
        const Expanded(child: SizedBox()),
      ]);
      await pumpV2(tester, _segments(v: v, inner: inner));
      await tester.fling(find.text('chip 1'), const Offset(-250, 0), 900);
      await tester.pumpAndSettle();
      expect(v.value, 'a');
      expect(find.text('chip 0'), findsNothing);
    });

    testWidgets('reduced motion: no follow while dragging, switches on release', (tester) async {
      final v = ValueNotifier('a');
      await pumpV2(tester, _segments(v: v), reducedMotion: true);
      final g = await tester.startGesture(tester.getCenter(find.text('a 3')));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 30));
        expect(_shift(tester), 0);
      }
      await g.up();
      await tester.pump();
      expect(v.value, 'b');
    });

    testWidgets('progress → MgSegmented thumb; at .5 it sits between 0 and 1', (tester) async {
      final p = ValueNotifier<double>(0.5);
      await pumpV2(
        tester,
        Center(
          child: SizedBox(
            width: 304,
            child: MgSegmented<String>(
              segments: const [MgSegment(value: 'a', label: 'A'), MgSegment(value: 'b', label: 'B'), MgSegment(value: 'c', label: 'C')],
              value: 'a',
              onChanged: (_) {},
              dragProgress: p,
              counts: const {'a': 3, 'b': 12},
              inlineCount: true,
            ),
          ),
        ),
      );
      await tester.pump();
      const segW = (304 - 8 - 2) / 3;
      final thumb = tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
      expect(thumb.left, closeTo(segW * 0.5, 0.01));
      expect(find.text('12'), findsOneWidget);
      p.value = 0;
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left, 0);
    });
  });

  testWidgets('MgSwipeSwitcher: reduced → the new content on the first pump', (tester) async {
    final k = ValueNotifier(1);
    await pumpV2(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: k,
        builder: (_, n, __) => MgSwipeSwitcher(switchKey: n, direction: 1, child: Text('page $n')),
      ),
      reducedMotion: true,
    );
    k.value = 2;
    await tester.pump();
    expect(find.text('page 2'), findsOneWidget);
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets('MgSwipeSwitcher animates the incoming page from the right', (tester) async {
    final k = ValueNotifier(1);
    await pumpV2(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: k,
        builder: (_, n, __) => MgSwipeSwitcher(switchKey: n, direction: 1, child: Text('page $n')),
      ),
    );
    final x0 = tester.getTopLeft(find.text('page 1')).dx;
    k.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getTopLeft(find.text('page 2')).dx, greaterThan(x0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('page 2')).dx, closeTo(x0, 0.5));
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets('MgStepFade keeps the field text across steps', (tester) async {
    final step = ValueNotifier(0);
    final ctrl = TextEditingController();
    await pumpV2(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: step,
        builder: (_, s, __) => MgStepFade(trigger: s, direction: 1, child: TextField(controller: ctrl)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Petra');
    step.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('Petra'), findsOneWidget);
  });

  group('MgEdgeBack', () {
    Future<int> drag(WidgetTester tester, TargetPlatform platform, double to) async {
      var backs = 0;
      tester.view.physicalSize = const Size(360, 780) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(body: MgEdgeBack(onBack: () => backs++, child: const ColoredBox(color: Colors.white, child: SizedBox.expand()))),
      ));
      final g = await tester.startGesture(const Offset(5, 300));
      const steps = 10;
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset((to - 5) / steps, 0));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await g.up();
      await tester.pumpAndSettle();
      return backs;
    }

    testWidgets('iOS 5 → 160 = back once', (tester) async => expect(await drag(tester, TargetPlatform.iOS, 160), 1));
    testWidgets('iOS 5 → 40 = nothing', (tester) async => expect(await drag(tester, TargetPlatform.iOS, 40), 0));
    testWidgets('Android = child only', (tester) async {
      expect(await drag(tester, TargetPlatform.android, 200), 0);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  testWidgets('MgSnapScrollPhysics: a fling settles on a whole card', (tester) async {
    final c = ScrollController();
    await pumpV2(
      tester,
      SizedBox(
        height: 120,
        child: ListView(
          controller: c,
          scrollDirection: Axis.horizontal,
          physics: const MgSnapScrollPhysics(itemExtent: 212),
          children: [for (var i = 0; i < 10; i++) SizedBox(width: 212, child: Text('card $i'))],
        ),
      ),
    );
    await tester.fling(find.text('card 0'), const Offset(-90, 0), 300);
    await tester.pumpAndSettle();
    expect(c.offset % 212, closeTo(0, 0.5));
    expect(c.offset, greaterThan(0));
    await tester.drag(find.text('card 1'), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(c.offset % 212, closeTo(0, 0.5));
    expect(MgSwipe.commitDistance, 72);
  });

  testWidgets('MgFilterChip tab style: selected night pill with neon count', (tester) async {
    await pumpV2(
      tester,
      const Row(children: [
        MgFilterChip(label: 'Jízdy', onTap: null, selected: true, count: 4, style: MgFilterChipStyle.tab),
        MgFilterChip(label: 'Trasy', onTap: null, count: 2, style: MgFilterChipStyle.tab),
      ]),
    );
    expect(find.text('Jízdy'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    final selected = tester.widget<Text>(find.text('Jízdy'));
    expect(selected.style?.color, Colors.white);
  });
}
