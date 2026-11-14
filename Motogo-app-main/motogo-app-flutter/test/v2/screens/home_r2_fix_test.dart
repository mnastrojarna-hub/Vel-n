// fix:home r2 — a range given for "today" is dropped once that day is in
// the past (midnight / resume, no restart); the header is the old one (no
// concierge / unread note — lookonly-fix:core); the funnel eyebrow stays labelled beside the
// pager when it fits; "Všechny trasy ›" moves under the title instead of
// splitting its words; the calculator disc and the funnel calendar button
// are CTA zones (the AI button yields instead of peeking over them).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/chrome/mg_fab_avoid.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_funnel_parts.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

String _s(String lang, String key) => translations[lang]![key]!;

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  test('a given range that started before "today" is no longer given', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final range = FunnelRange(day(0), day(2));
    c.read(funnelGivenProvider.notifier).state = range;
    expect(c.read(funnelSelectionProvider).given, range);
    c.read(funnelTodayProvider.notifier).state = day(1);
    expect(c.read(funnelSelectionProvider).given, isNull);
    // v5.0.1: not given = no dates (no preselected weekend).
    expect(c.read(funnelSelectionProvider).range(day(1)), isNull);
  });

  testWidgets('the funnel moves "today" on (stale day, app resumed)', (t) async {
    await pumpV2(t, const SingleChildScrollView(child: HomeFunnelV2()), overrides: homeOverrides(funnel: kMotos.take(2).toList()));
    await _frames(t);
    final c = ProviderScope.containerOf(t.element(find.byType(HomeFunnelV2)));
    c.read(funnelTodayProvider.notifier).state = day(-1);
    await _frames(t);
    expect(c.read(funnelTodayProvider), day(0), reason: 'a build on a stale day re-syncs it');
    c.read(funnelTodayProvider.notifier).state = day(-1);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(c.read(funnelTodayProvider), day(0), reason: 'resume re-syncs it');
    expect(t.takeException(), isNull);
    await _end(t);
  });

  testWidgets('header = the old one ("jen vzhled"): no concierge / unread note, pilot + search, banner last', (t) async {
    final msg = _s('cs', 'v2HomeNoteMsg').split('{title}').first.trim();
    final idle = _s('cs', 'v2HomeNoteIdle');
    for (final banner in [true, false]) {
      await pumpV2(t, const HomeScreenV2(), overrides: homeOverrides(funnel: kMotos.take(2).toList(), banner: banner));
      await _frames(t);
      expect(find.textContaining(msg), findsNothing);
      expect(find.text(idle), findsNothing);
      expect(find.text('PILOT: Jan'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
      expect(find.textContaining('zavřeno'), banner ? findsWidgets : findsNothing);
      expect(t.takeException(), isNull);
      await _end(t);
    }
  });

  for (final (w, full) in [(326.0, true), (250.0, false)]) {
    testWidgets('funnel eyebrow beside the pager · ${w.toInt()} px', (t) async {
      await pumpV2(
          t,
          Center(child: SizedBox(width: w, child: FunnelTopRow(count: 4, index: 0, onNext: () {}))),
          overrides: homeOverrides());
      await t.pump();
      final label = _s('cs', 'v2HomeFnEyebrow');
      expect(find.text(label.toUpperCase()), full ? findsOneWidget : findsNothing);
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), findsOneWidget);
      expect(find.text('1 / 4'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('funnel calendar = CTA zone', (t) async {
    await pumpV2(t, const SingleChildScrollView(child: Column(children: [HomeFunnelV2()])),
        overrides: homeOverrides(funnel: kMotos.take(2).toList()));
    await _frames(t);
    expect(
        t
            .widgetList<MgFabAvoid>(find.ancestor(
                of: find.descendant(of: find.byType(FunnelPresets), matching: find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.calendarCheck)),
                matching: find.byType(MgFabAvoid)))
            .first
            .kind,
        MgAvoidKind.cta);
    expect(t.takeException(), isNull);
    await _end(t);
  });
}
