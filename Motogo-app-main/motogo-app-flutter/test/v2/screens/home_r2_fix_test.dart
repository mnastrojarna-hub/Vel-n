// fix:home r2 — a range given for "today" is dropped once that day is in
// the past (midnight / resume, no restart); the header never repeats the
// unread message ("MotoGo ti píše" shows it) and keeps the S0 idle line
// only without a Velín banner; the funnel eyebrow stays labelled beside the
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
import 'package:motogo_app/core/v2/widgets/mg_section.dart';
import 'package:motogo_app/features/home/v2/funnel_provider.dart';
import 'package:motogo_app/features/home/v2/home_funnel_parts.dart';
import 'package:motogo_app/features/home/v2/home_funnel_v2.dart';
import 'package:motogo_app/features/home/v2/home_next_pill_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_section_head.dart';
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

MgAvoidKind _zoneOf(WidgetTester t, String icon) => t
    .widget<MgFabAvoid>(find
        .ancestor(of: find.byWidgetPredicate((w) => w is MgIcon && w.name == icon), matching: find.byType(MgFabAvoid))
        .first)
    .kind;

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
    expect(c.read(funnelSelectionProvider).range(day(1)), funnelPresets(day(1)).$1);
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

  testWidgets('header: no repeated unread message, idle line only without a banner', (t) async {
    final msg = _s('cs', 'v2HomeNoteMsg').split('{title}').first.trim();
    final idle = _s('cs', 'v2HomeNoteIdle');
    await pumpV2(t, const HomeScreenV2(), overrides: homeOverrides(funnel: kMotos.take(2).toList()));
    await _frames(t);
    expect(find.textContaining(msg), findsNothing);
    expect(find.text(idle), findsNothing, reason: 'S0 with the Velín banner: no idle line');
    await _end(t);

    await pumpV2(t, const HomeScreenV2(), overrides: homeOverrides(funnel: kMotos.take(2).toList(), banner: false));
    await _frames(t);
    expect(find.text(idle), findsOneWidget);
    expect(find.textContaining(msg), findsNothing);
    await _end(t);

    await pumpV2(t, const HomeScreenV2(), overrides: homeOverrides(reservations: [res('b4', status: 'reserved', from: 3, to: 5)]));
    await _frames(t);
    expect(find.textContaining(msg), findsNothing, reason: 'S4: the message row shows it, not the header');
    expect(t.takeException(), isNull);
    await _end(t);
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

  testWidgets('"Všechny trasy ›" goes under the title instead of splitting a word', (t) async {
    late bool fr, cs;
    await pumpV2(t, Builder(builder: (c) {
      cs = HomeSectionHead.linkInline(c, _s('cs', 'v2HomeRoutesPopular'), _s('cs', 'v2HomeRoutesAll'), 390);
      return const SizedBox();
    }));
    expect(cs, isTrue);
    await pumpV2(
        t,
        Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Builder(builder: (c) {
              fr = HomeSectionHead.linkInline(c, _s('fr', 'v2HomeRoutesPopular'), _s('fr', 'v2HomeRoutesAll'), 320);
              return HomeSectionHead(
                  title: _s('fr', 'v2HomeRoutesPopular'), link: _s('fr', 'v2HomeRoutesAll'), onLink: () {});
            }),
          ),
        ),
        lang: 'fr',
        size: const Size(320, 690));
    await t.pump();
    expect(fr, isFalse);
    final title = t.getRect(find.text(_s('fr', 'v2HomeRoutesPopular')));
    final link = t.getRect(find.byType(MgTextLink));
    expect(link.top, greaterThanOrEqualTo(title.bottom - 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('calculator disc and funnel calendar = CTA zones, the pill a tap zone', (t) async {
    await pumpV2(t, const SingleChildScrollView(child: Column(children: [HomeNextPillV2(), HomeFunnelV2()])),
        overrides: homeOverrides(funnel: kMotos.take(2).toList()));
    await _frames(t);
    expect(_zoneOf(t, MgIcons.calc), MgAvoidKind.cta);
    expect(_zoneOf(t, MgIcons.chevronRight), MgAvoidKind.tap); // the pill
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
