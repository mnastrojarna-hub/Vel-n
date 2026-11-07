// FND-11 disclosure / count-up / one-shot progress, FND-12 display
// formatting, FND-13 skeleton shapes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_count_up.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/motion/mg_once_progress.dart';
import 'package:motogo_app/core/v2/tokens/mg_format.dart';
import 'package:motogo_app/core/v2/widgets/mg_disclosure.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';

import '../support/v2_harness.dart';

const _nb = ' ';

class _Force extends StatefulWidget {
  const _Force();
  @override
  State<_Force> createState() => _ForceState();
}

class _ForceState extends State<_Force> {
  bool force = false;
  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(onPressed: () => setState(() => force = !force), child: const Text('toggle')),
        MgDisclosure(label: 'Technické detaily', forceExpanded: force, child: const Text('detail body')),
      ]);
}

void main() {
  setUp(MgMotion.resetSession);

  group('MgDisclosure', () {
    testWidgets('collapsed by default; tap opens, tap closes', (tester) async {
      final seen = <bool>[];
      await pumpV2(tester, MgDisclosure(label: 'Více', expandedLabel: 'Méně', onChanged: seen.add, child: const Text('extra')));
      expect(find.text('extra'), findsNothing);
      await tester.tap(find.text('Více'));
      await tester.pumpAndSettle();
      expect(find.text('extra'), findsOneWidget);
      expect(find.text('Méně'), findsOneWidget);
      await tester.tap(find.text('Méně'));
      await tester.pumpAndSettle();
      expect(find.text('extra'), findsNothing);
      expect(seen, [true, false]);
    });

    testWidgets('forceExpanded opens it and it stays open after the flag drops', (tester) async {
      await pumpV2(tester, const _Force());
      expect(find.text('detail body'), findsNothing);
      await tester.tap(find.text('toggle'));
      await tester.pumpAndSettle();
      expect(find.text('detail body'), findsOneWidget);
      await tester.tap(find.text('toggle'));
      await tester.pumpAndSettle();
      expect(find.text('detail body'), findsOneWidget);
      await tester.tap(find.text('Technické detaily'));
      await tester.pumpAndSettle();
      expect(find.text('detail body'), findsNothing);
    });

    testWidgets('reduced motion: opens in one frame, semantics expanded', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpV2(tester, const MgDisclosure(label: 'Více', child: Text('extra')), reducedMotion: true);
      await tester.tap(find.text('Více'));
      await tester.pump();
      expect(find.text('extra'), findsOneWidget);
      expect(find.byType(AnimatedSize), findsNothing);
      expect(tester.getSemantics(find.text('Více')), matchesSemantics(isButton: true, hasExpandedState: true, isExpanded: true, hasTapAction: true, label: 'Více'));
      handle.dispose();
    });
  });

  group('MgCountUp / MgOnceProgress', () {
    testWidgets('counts once per session key, final at once afterwards', (tester) async {
      String f(num v) => '${v.round()} km';
      await pumpV2(tester, MgCountUp(value: 1200, format: f, sessionKey: 'km'));
      await tester.pump(const Duration(milliseconds: 200));
      final mid = int.parse((tester.widget<Text>(find.byType(Text)).data!).split(' ').first);
      expect(mid, inExclusiveRange(0, 1200));
      await tester.pumpAndSettle();
      expect(find.text('1200 km'), findsOneWidget);
      await pumpV2(tester, const SizedBox());
      await pumpV2(tester, MgCountUp(value: 1200, format: f, sessionKey: 'km'));
      expect(find.text('1200 km'), findsOneWidget);
    });

    testWidgets('reduced motion: final value / t = 1 on the first frame', (tester) async {
      await pumpV2(
        tester,
        Column(children: [
          MgCountUp(value: 7, format: (v) => 'rides $v', sessionKey: 'r'),
          MgOnceProgress(duration: const Duration(seconds: 1), builder: (_, t) => Text('t=$t')),
        ]),
        reducedMotion: true,
      );
      expect(find.text('rides 7'), findsOneWidget);
      expect(find.text('t=1.0'), findsOneWidget);
    });

    testWidgets('MgOnceProgress runs 0 → 1 once', (tester) async {
      await pumpV2(tester, MgOnceProgress(duration: const Duration(milliseconds: 300), curve: Curves.linear, sessionKey: 'p', builder: (_, t) => Text('t=${t.toStringAsFixed(1)}')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('t=0.5'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('t=1.0'), findsOneWidget);
    });
  });

  group('mg_format', () {
    final now = DateTime(2026, 11, 7);
    test('numbers, km, rating', () {
      expect(mgNum(12027, 'cs'), '12${_nb}027');
      expect(mgNum(12027, 'en'), '12,027');
      expect(mgNum(12027, 'de'), '12.027');
      expect(mgNum(12027, 'uk'), '12${_nb}027');
      expect(mgKm(1.24, 'cs'), '1,2${_nb}km');
      expect(mgKm(128.4, 'en'), '128${_nb}km');
      expect(mgRating(4.66, 'cs'), '4,7');
      expect(mgRating(4.66, 'en'), '4.7');
      expect(mgMeters(850.4, 'de'), '850${_nb}m');
    });

    test('NBSP before the currency and inside day counts', () {
      expect(mgNbsp('12 027 Kč'), '12${_nb}027${_nb}Kč');
      expect(mgNbsp('celkem 3 dny'), 'celkem 3${_nb}dny');
      expect(mgNbsp('2 Tage · 49 €'), '2\u00A0Tage · 49\u00A0€');
      expect(mgNbsp('5 днів'), '5\u00A0днів');
      expect(mgNbsp('3 dnyX'), '3 dnyX');
    });

    test('short dates and ranges', () {
      expect(mgDayShort(DateTime(2026, 10, 23), 'cs', now: now), 'pá${_nb}23.${_nb}10.');
      expect(mgDayShort(DateTime(2027, 1, 4), 'cs', now: now), 'po${_nb}4.${_nb}1.${_nb}2027');
      expect(mgRange(DateTime(2026, 10, 23), DateTime(2026, 10, 25), 'cs', now: now),
          'pá${_nb}23.${_nb}10. → ne${_nb}25.${_nb}10.');
      expect(mgDayShort(DateTime(2026, 10, 23), 'en', now: now), 'Fri${_nb}23/10');
      expect(mgDayShort(DateTime(2026, 10, 23), 'de', now: now), startsWith('Fr'));
      expect(mgDayShort(DateTime(2026, 10, 23), 'uk', now: now), startsWith('пт'));
    });
  });

  testWidgets('skeleton row / photo card: final geometry, no ticker under reduced motion', (tester) async {
    await pumpV2(
      tester,
      const Column(children: [
        MgSkeletonRow(trailing: 60),
        SizedBox(height: 12),
        MgSkeletonPhotoCard(photoHeight: 180, ctaHeight: 48, pills: [60, 80]),
      ]),
      reducedMotion: true,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getSize(find.byType(MgSkeletonRow)).height, 56);
    expect(find.byType(MgSkeleton), findsWidgets);
    await pumpV2(tester, const MgSkeletonRow());
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });
}
